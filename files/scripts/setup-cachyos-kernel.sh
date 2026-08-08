#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing CachyOS BORE kernel from COPR ==="

install_available \
  git make gcc elfutils-libelf-devel

echo "--- Installing kernel-cachyos packages ---"

install_available \
  kernel-cachyos kernel-cachyos-core kernel-cachyos-modules \
  kernel-cachyos-devel kernel-cachyos-devel-matched

if ! rpm -q kernel-cachyos-core kernel-cachyos-devel >/dev/null 2>&1; then
  echo "ERROR: kernel-cachyos packages not available from the enabled repositories" >&2
  exit 1
fi

echo "--- Replacing stock kernel ---"

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

if ! retry git ls-remote --exit-code --tags \
    "https://github.com/NVIDIA/open-gpu-kernel-modules.git" \
    "refs/tags/${NV_USR_VER}" >/dev/null 2>&1; then
  echo "ERROR: no open-gpu-kernel-modules tag ${NV_USR_VER} upstream; refusing to build a mismatched module" >&2
  exit 1
fi

rm -rf /tmp/ogkm
retry git clone --depth 1 --branch "${NV_USR_VER}" \
  "https://github.com/NVIDIA/open-gpu-kernel-modules.git" /tmp/ogkm

make -C /tmp/ogkm -j"$(nproc)" modules \
  SYSSRC="/usr/src/kernels/${KVER}" SYSOUT="/usr/src/kernels/${KVER}" \
  > /tmp/ogkm-build.log 2>&1
grep -vE "objtool: .*'?naked'? return found in .*RETHUNK build" /tmp/ogkm-build.log || true
make -C /tmp/ogkm modules_install \
  SYSSRC="/usr/src/kernels/${KVER}" SYSOUT="/usr/src/kernels/${KVER}" \
  > /tmp/ogkm-install.log 2>&1
grep -vE "objtool: .*'?naked'? return found in .*RETHUNK build" /tmp/ogkm-install.log || true
depmod -a "${KVER}"

echo "--- Generating initramfs for ${KVER} ---"

install_available dracut
install_available ostree
if [[ ! -x /usr/lib/ostree/ostree-prepare-root ]]; then
  echo "ERROR: /usr/lib/ostree/ostree-prepare-root missing; cannot build a bootable initramfs" >&2
  exit 1
fi

install -d -m 0755 /etc/dracut.conf.d
cat >/etc/dracut.conf.d/99-vibes-ostree.conf <<'CONF'
add_dracutmodules+=" ostree "
CONF

DRACUT_NO_XATTR=1 dracut --no-hostonly --no-hostonly-cmdline --force \
  --reproducible -v --add 'ostree' \
  "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}" 2>&1 | tee /tmp/dracut.log
chmod 0600 "/usr/lib/modules/${KVER}/initramfs.img"

if ! grep -q 'ostree' /tmp/dracut.log; then
  echo "ERROR: ostree dracut module was not included in the initramfs" >&2
  echo "--- dracut log ---" >&2
  tail -n 40 /tmp/dracut.log >&2 || true
  rm -f /tmp/dracut.log
  exit 1
fi
rm -f /tmp/dracut.log

echo "--- Disabling zram-generator (zswap is default-on in the CachyOS kernel) ---"
if rpm -q zram-generator-defaults >/dev/null 2>&1; then
  "${DNF[@]}" remove --no-autoremove zram-generator-defaults || true
fi

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

echo "--- Cleaning up ---"
rm -rf /tmp/ogkm
clean_build_artifacts

echo "=== CachyOS BORE kernel installed successfully (${KVER}) ==="
