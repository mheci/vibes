#!/usr/bin/env bash
# Install the CachyOS BORE kernel (kernel-cachyos) from the official
# bieszczaders/kernel-cachyos COPR (see setup-repos-and-rpms.sh), replacing
# the stock Bluefin kernel, and rebuild the NVIDIA open kernel modules
# in-container so they match the new kernel.
#
# Why the COPR instead of building from source?
#   A full rpmbuild of the kernel on GitHub Actions runners (2-4 cores) took
#   1h+ per image build. The COPR is maintained by the CachyOS Fedora porter
#   from the official CachyOS/copr-linux-cachyos sources, tracks the
#   CachyOS/linux tags, and is rebuilt on upstream infrastructure, so the
#   kernel is always current with zero build time in this image.
#
# What the COPR kernel provides (same or similar to the previous source
# build): BORE scheduler + Cachy Sauce patchset, HZ=1000, x86_64-v3
# (X86_64_VERSION=3), PREEMPT_DYNAMIC (full preemption, runtime-selectable),
# NO_HZ_FULL (full tickless), NUMA, sched_ext (scx), ntsync, zswap default-on
# (zstd), SELinux default LSM.
#
# Tradeoffs vs. building ourselves:
#   - The COPR does not ship the LTO variant (kernel-cachyos-lto); the shipped
#     kernel is the plain CachyOS default (gcc, -O2). LTO/-O3 are compile-time
#     only and not available without rebuilding from source.
#   - No znver3 march exists in kernel 7.x Kconfig; x86-64-v3 is the closest
#     portable ISA target (covers Zen3+), matching CachyOS's Fedora builds.
#   - Default TCP congestion control stays "cubic" (BBR3 is shipped as a
#     module and enabled at runtime via sysctl, see files/system/etc), and the
#     default governor stays "schedutil" (set to "performance" at runtime via
#     a udev rule).
#   - NUMA stays enabled: harmless on single-socket desktops and needed for
#     correct behavior on multi-socket systems; no measurable penalty on
#     gaming desktops.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing CachyOS BORE kernel from COPR ==="

# =============================================================================
# Build dependencies for the NVIDIA kmod rebuild below
# (git/make/gcc are already installed by setup-repos-and-rpms.sh; kept here
# for robustness and idempotency)
# =============================================================================
install_available \
  git make gcc elfutils-libelf-devel

# =============================================================================
# Install the COPR kernel (BORE, HZ=1000, x86_64-v3, sched_ext, ntsync).
# devel + devel-matched are required to build the NVIDIA modules and to
# satisfy kernel-devel-matched providers.
# =============================================================================
echo "--- Installing kernel-cachyos packages ---"

install_available \
  kernel-cachyos kernel-cachyos-core kernel-cachyos-modules \
  kernel-cachyos-devel kernel-cachyos-devel-matched

if ! rpm -q kernel-cachyos-core kernel-cachyos-devel >/dev/null 2>&1; then
  echo "ERROR: kernel-cachyos packages not available from the enabled repositories" >&2
  exit 1
fi

# =============================================================================
# Replace the stock Bluefin kernel (Bazzite/Bluefin proven pattern)
# =============================================================================
echo "--- Replacing stock kernel ---"

# 1. Remove the stock kernel packages and any akmods built for it.
STOCK_KERNEL_PKGS=(
  kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
  kernel-devel kernel-devel-matched kernel-tools kernel-tools-libs
)
for pkg in "${STOCK_KERNEL_PKGS[@]}"; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    rpm -e --nodeps "${pkg}" || true
  fi
done
for pkg in $(rpm -qa 'kmod-nvidia*' 'akmod-nvidia*' 2>/dev/null); do
  rpm -e --nodeps "${pkg}" || true
done

# 2. Determine the installed kernel version (rpm is authoritative; the
#    modules dir is not wiped here because rpm -e above removed the stock
#    module trees on its own).

# 3. Lock the stock kernel names so `dnf upgrade` never pulls them back.
KVER="$(rpm -q kernel-cachyos-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}' 2>/dev/null || true)"
if [[ -z "${KVER}" ]]; then
  echo "ERROR: cachyos kernel not installed (kernel-cachyos-core rpm missing)" >&2
  exit 1
fi
echo "Installed kernel: ${KVER}"
install -d -m 0755 /usr/share/vibes
echo "${KVER}" >/usr/share/vibes/kernel-version

LOCKED_PKGS=(
  kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
  kernel-devel kernel-devel-matched kernel-tools kernel-tools-libs
)
if command -v dnf5 >/dev/null 2>&1 && dnf5 versionlock add "${LOCKED_PKGS[@]}" >/dev/null 2>&1; then
  echo "Kernel packages version-locked via dnf5"
else
  install -d -m 0755 /etc/dnf
  : >/etc/dnf/versionlock.list
  for pkg in "${LOCKED_PKGS[@]}"; do
    echo "${pkg}" >>/etc/dnf/versionlock.list
  done
  echo "Kernel packages version-locked via /etc/dnf/versionlock.list"
fi

# =============================================================================
# Rebuild NVIDIA open kernel modules in-container for the new kernel
# =============================================================================
echo "--- Rebuilding NVIDIA open kernel modules ---"

NV_USR_VER=""
for pkg in xorg-x11-drv-nvidia nvidia-driver; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    NV_USR_VER="$(rpm -q --qf '%{VERSION}' "${pkg}")"
    break
  fi
done
if [[ -z "${NV_USR_VER}" ]]; then
  echo "ERROR: could not determine NVIDIA userspace driver version (nvidia-driver RPM not found)" >&2
  exit 1
fi
echo "NVIDIA userspace driver version: ${NV_USR_VER}"

# The kernel module must be built from the tag matching the userspace driver.
if ! retry git ls-remote --exit-code --tags \
    "https://github.com/NVIDIA/open-gpu-kernel-modules.git" \
    "refs/tags/${NV_USR_VER}" >/dev/null 2>&1; then
  echo "ERROR: no open-gpu-kernel-modules tag ${NV_USR_VER} upstream; refusing to build a mismatched module" >&2
  exit 1
fi

rm -rf /tmp/ogkm
retry git clone --depth 1 --branch "${NV_USR_VER}" \
  "https://github.com/NVIDIA/open-gpu-kernel-modules.git" /tmp/ogkm

# SYSSRC/SYSOUT target the CachyOS kernel tree (gcc-built, matching gcc).
#
# objtool (CONFIG_MITIGATION_RETHUNK) flags the NVIDIA pre-compiled blobs'
# plain `ret` instructions as 'naked return found in MITIGATION_RETHUNK
# build'. These warnings are benign (the blobs are shipped without
# -mfunction-return=thunk-extern). Do NOT disable objtool for these objects
# by setting OBJECT_FILES_NON_STANDARD: skipping objtool also skips the
# static_branch JMP->NOP conversion and crashes nvidia-modeset on suspend
# (NVIDIA/open-gpu-kernel-modules#1095). Keep objtool enabled and only
# filter the known-benign warning lines from the build log.
make -C /tmp/ogkm -j"$(nproc)" modules \
  SYSSRC="/usr/src/kernels/${KVER}" SYSOUT="/usr/src/kernels/${KVER}" 2>&1 \
  | grep -vE "objtool: .*'?naked'? return found in .*RETHUNK build"
make -C /tmp/ogkm modules_install \
  SYSSRC="/usr/src/kernels/${KVER}" SYSOUT="/usr/src/kernels/${KVER}" 2>&1 \
  | grep -vE "objtool: .*'?naked'? return found in .*RETHUNK build"
depmod -a "${KVER}"

# =============================================================================
# Generate the initramfs for the CachyOS kernel
#
# bootc images ship the initramfs inside the container at
# /usr/lib/modules/<kver>/initramfs.img (Fedora/RHEL bootc docs); `bootc
# install to-disk` copies it into the deployment and references it from the
# bootloader entry. The Bluefin base only shipped one for the stock kernel,
# which the swap above removed, so without this step the installed system
# boots the CachyOS kernel with no initrd: the kernel cannot mount the xfs
# root (xfs/virtio are modules, not builtins, in the CachyOS config) and
# panics with "VFS: Unable to mount root fs on unknown-block(0,0)". This
# was caught by the nightly QEMU boot test.
#
# The ostree dracut module (99ostree) provides ostree-prepare-root, without
# which the initramfs cannot find/mount the ostree deployment at all. Its
# module-setup check() returns 1 (hard "do not include", which --add cannot
# override) unless BOTH systemd and /usr/lib/ostree/ostree-prepare-root are
# present; only then does it return 255 ("include when explicitly requested",
# which --add 'ostree' honors). Verified in CI: the module is included
# ("*** Including module: ostree ***") and the image builds cleanly, so we
# (a) guarantee the binary via the ostree RPM and (b) still force the module
# both on the command line and via a dracut.conf.d drop-in (belt and
# suspenders), exactly the ublue (19-initramfs.sh) and RHCOS recipe.
# DRACUT_NO_XATTR avoids xattr failures under the container storage driver;
# --reproducible matches the ublue recipe for bit-identical initramfs.
# =============================================================================
echo "--- Generating initramfs for ${KVER} ---"

install_available dracut
# Package that ships /usr/lib/ostree/ostree-prepare-root and the 99ostree
# dracut module; without the binary the module-setup check() returns 1 and
# the module is silently dropped even with --add 'ostree'.
install_available ostree
if [[ ! -x /usr/lib/ostree/ostree-prepare-root ]]; then
  echo "ERROR: /usr/lib/ostree/ostree-prepare-root missing; cannot build a bootable initramfs" >&2
  exit 1
fi

# Belt and suspenders: also request the module via dracut.conf.d.
install -d -m 0755 /etc/dracut.conf.d
cat >/etc/dracut.conf.d/99-vibes-ostree.conf <<'CONF'
add_dracutmodules+=" ostree "
CONF

DRACUT_NO_XATTR=1 dracut --no-hostonly --no-hostonly-cmdline --force \
  --reproducible -v --add 'ostree' \
  "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}" 2>&1 | tee /tmp/dracut.log
chmod 0600 "/usr/lib/modules/${KVER}/initramfs.img"

# Fail loudly instead of letting a silently-missing module slip into the image
# (the smoke check below would catch it, but this surfaces the reason from the
# dracut log itself).
if ! grep -q 'ostree' /tmp/dracut.log; then
  echo "ERROR: ostree dracut module was not included in the initramfs" >&2
  echo "--- dracut log ---" >&2
  tail -n 40 /tmp/dracut.log >&2 || true
  rm -f /tmp/dracut.log
  exit 1
fi
rm -f /tmp/dracut.log

# =============================================================================
# zram-generator-defaults is redundant: the CachyOS kernel enables zswap by
# default (CONFIG_ZSWAP_DEFAULT_ON, zstd), so drop the zram swap unit.
# =============================================================================
echo "--- Disabling zram-generator (zswap is default-on in the CachyOS kernel) ---"
if rpm -q zram-generator-defaults >/dev/null 2>&1; then
  "${DNF[@]}" remove --no-autoremove zram-generator-defaults || true
fi

# =============================================================================
# Post-install smoke checks
# =============================================================================
echo "=== Running kernel smoke checks ==="
errors=0

check_kernel_file() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  OK: ${path}"
  else
    echo "  FAIL: ${path} not found" >&2
    errors=$((errors + 1))
  fi
}

check_kernel_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "${pattern}" "${file}" 2>/dev/null; then
    echo "  OK: ${label}"
  else
    echo "  FAIL: ${label} not found in ${file}" >&2
    errors=$((errors + 1))
  fi
}

check_kernel_file "/usr/lib/modules/${KVER}/vmlinuz"
check_kernel_file "/usr/lib/modules/${KVER}/initramfs.img"

check_initramfs_has() {
  local img="$1" needle="$2" label="$3"
  local listing dec bin
  listing="$(lsinitrd "${img}" 2>&1)"
  if grep -q "${needle}" <<<"${listing}"; then
    echo "  OK: ${label}"
    return 0
  fi
  # lsinitrd can fail to parse the image inside the build container (e.g. a
  # decompressor binary missing from the stage), so fall back to inspecting
  # the raw cpio archive directly before declaring the initramfs broken.
  for dec in "zstd -dc" "xz -dc" "gzip -dc" "bzip2 -dc" "lz4 -dc"; do
    bin="${dec%% *}"
    if command -v "${bin}" >/dev/null 2>&1 &&
       ${dec} "${img}" 2>/dev/null | cpio -t 2>/dev/null | grep -q "${needle}"; then
      echo "  OK: ${label} (via ${bin}+cpio fallback)"
      return 0
    fi
  done
  echo "  FAIL: ${label} not found in initramfs" >&2
  echo "  --- lsinitrd output (tail) ---" >&2
  echo "${listing}" | tail -n 40 >&2
  errors=$((errors + 1))
}

check_initramfs_has "/usr/lib/modules/${KVER}/initramfs.img" \
  'ostree-prepare-root' "initramfs contains ostree-prepare-root"
check_kernel_file "/usr/src/kernels/${KVER}/include/config/auto.conf"
check_kernel_file "/usr/src/kernels/${KVER}/.config"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_SCHED_CLASS_EXT=y" "sched_ext support"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_SCHED_BORE=y" "BORE scheduler"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_NTSYNC=m" "ntsync (module)"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_ZSWAP_DEFAULT_ON=y" "zswap default-on"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_LTO_NONE=y" "non-LTO build (COPR default)"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "^CONFIG_HZ=1000$" "HZ=1000 tick rate"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_X86_64_VERSION=3" "x86_64-v3 ISA"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_NO_HZ_FULL=y" "full tickless (NO_HZ_FULL)"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_PREEMPT_DYNAMIC=y" "runtime preemption (PREEMPT_DYNAMIC)"
check_kernel_grep "/usr/src/kernels/${KVER}/.config" "CONFIG_NUMA=y" "NUMA support"

if rpm -q kernel-cachyos-core kernel-cachyos-modules \
    kernel-cachyos-devel kernel-cachyos-devel-matched >/dev/null 2>&1; then
  echo "  OK: kernel-cachyos RPMs installed"
else
  echo "  FAIL: kernel-cachyos RPMs not all installed" >&2
  errors=$((errors + 1))
fi

if rpm -q kernel-core >/dev/null 2>&1; then
  echo "  FAIL: stock kernel-core is still installed" >&2
  errors=$((errors + 1))
else
  echo "  OK: stock kernel removed"
fi

if find "/usr/lib/modules/${KVER}" -name 'nvidia*.ko*' | grep -q .; then
  echo "  OK: NVIDIA open modules present for ${KVER}"
else
  echo "  FAIL: no NVIDIA modules found for ${KVER}" >&2
  errors=$((errors + 1))
fi

# dnf5's versionlock plugin stores locks in its own config files
# (/etc/dnf/versionlock.d/*.list) rather than the legacy
# /etc/dnf/versionlock.list, so verify whichever mechanism is present.
versionlock_ok=0
if [[ -f /etc/dnf/versionlock.list ]] && grep -q '^kernel' /etc/dnf/versionlock.list; then
  versionlock_ok=1
fi
if [[ ${versionlock_ok} -eq 0 ]] && ! grep -qs '^kernel' /etc/dnf/versionlock.d/*.list 2>/dev/null; then
  versionlock_out="$(dnf5 versionlock list 2>&1 || true)"
  if grep -q 'kernel' <<<"${versionlock_out}"; then
    versionlock_ok=1
  fi
fi
if [[ ${versionlock_ok} -eq 1 ]]; then
  echo "  OK: kernel packages version-locked"
else
  echo "  FAIL: kernel packages not version-locked" >&2
  echo "  --- /etc/dnf/versionlock.list ---" >&2
  cat /etc/dnf/versionlock.list >&2 2>/dev/null || true
  echo "  --- /etc/dnf/versionlock.d ---" >&2
  ls -la /etc/dnf/versionlock.d >&2 2>/dev/null || true
  cat /etc/dnf/versionlock.d/*.list >&2 2>/dev/null || true
  echo "  --- dnf5 versionlock list ---" >&2
  echo "${versionlock_out}" >&2
  errors=$((errors + 1))
fi

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} kernel smoke check(s) failed" >&2
  exit 1
fi

# =============================================================================
# Cleanup
# =============================================================================
echo "--- Cleaning up ---"
rm -rf /tmp/ogkm
clean_build_artifacts

echo "=== CachyOS BORE kernel installed successfully (${KVER}) ==="
