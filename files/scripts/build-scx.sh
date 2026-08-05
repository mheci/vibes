#!/usr/bin/env bash
# Build and install the latest sched-ext/scx schedulers AND the scx_loader
# toolchain (scx_loader/scxctl/scxtui) from upstream git, replacing the
# COPR-provided scx-scheds/scx-tools-git packages (which are pinned to an
# older commit). The schedulers build follows the CachyOS scx-scheds-git
# spec (cargo fetch + workspace build with the same crate exclusions);
# scx_loader moved to its own repository (sched-ext/scx-loader) and is no
# longer part of the scx workspace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building latest sched-ext/scx from source ==="

# =============================================================================
# Build dependencies (idempotent - already-installed packages are skipped)
# =============================================================================
echo "--- Installing scx build dependencies ---"

install_available \
  cargo rust clang lld llvm bpftool \
  elfutils-libelf-devel libbpf-devel protobuf-compiler libseccomp-devel \
  jq jq-devel zlib openssl-devel

# =============================================================================
# Remove the COPR packages so the from-source build owns the binaries
# =============================================================================
echo "--- Removing COPR scx packages ---"

for pkg in scx-scheds scx-tools-git; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    rpm -e --nodeps "${pkg}" || true
  fi
done

# =============================================================================
# Build from upstream git HEAD
# =============================================================================
echo "--- Cloning sched-ext/scx ---"

SCX_COMMIT=""
rm -rf /tmp/scx /tmp/scx-cargo
retry git clone --depth 1 https://github.com/sched-ext/scx.git /tmp/scx
SCX_COMMIT="$(git -C /tmp/scx rev-parse --short HEAD)"
echo "scx commit: ${SCX_COMMIT}"

echo "--- Building scx schedulers (cargo, release) ---"
export CARGO_HOME=/tmp/scx-cargo
cd /tmp/scx

retry cargo fetch --locked
retry cargo build \
  --release \
  --frozen \
  --workspace \
  --exclude scx_rlfifo \
  --exclude scx_mitosis \
  --exclude xtask \
  --exclude scx_characterize \
  --exclude vmlinux_docify \
  --exclude scx_arena_selftests

echo "--- Installing scx binaries ---"
# Install all built executables (skip .so and .d files), as the CachyOS spec
# does - this covers scx_loader and every scheduler binary.
find target/release -maxdepth 1 -type f -executable ! -name '*.so' \
  -exec install -Dm755 -t /usr/bin {} +

# =============================================================================
# Build the scx_loader toolchain (scx_loader daemon, scxctl CLI, scxtui TUI)
# from its own repository - the loader was split out of the scx workspace.
# =============================================================================
echo "--- Building scx_loader/scxctl/scxtui (sched-ext/scx-loader) ---"

SCX_LOADER_COMMIT=""
rm -rf /tmp/scx-loader
retry git clone --depth 1 https://github.com/sched-ext/scx-loader.git /tmp/scx-loader
SCX_LOADER_COMMIT="$(git -C /tmp/scx-loader rev-parse --short HEAD)"
echo "scx-loader commit: ${SCX_LOADER_COMMIT}"

cd /tmp/scx-loader
# No --frozen here: the upstream Cargo.lock can lag behind Cargo.toml
# (e.g. a missing zbus_polkit entry), which cargo must be allowed to fix.
retry cargo build --release

echo "--- Installing scx_loader toolchain ---"
find target/release -maxdepth 1 -type f -executable ! -name '*.so' \
  -exec install -Dm755 -t /usr/bin {} +

# Systemd unit, D-Bus activation/policy and config files shipped upstream.
install -Dm644 services/scx_loader.service -t /usr/lib/systemd/system/
install -Dm644 services/org.scx.Loader.service -t /usr/share/dbus-1/system-services/
install -Dm644 configs/org.scx.Loader.conf -t /usr/share/dbus-1/system.d/
install -Dm644 configs/org.scx.Loader.xml -t /usr/share/dbus-1/interfaces/
install -Dm644 configs/org.scx.Loader.policy -t /usr/share/polkit-1/actions/
VENDOR_CONFIG_INSTALLED=0
if [[ -f configs/scx_loader.toml ]]; then
  install -d -m 0755 /usr/share/scx_loader
  install -m 0644 configs/scx_loader.toml /usr/share/scx_loader/config.toml
  VENDOR_CONFIG_INSTALLED=1
fi

# =============================================================================
# Runtime configuration: loader unit + default scheduler
# (/etc/scx_loader/config.toml is the first entry in the lookup order)
# =============================================================================
echo "--- Configuring scx_loader ---"

install -d -m 0755 /etc/scx_loader
cat >/etc/scx_loader/config.toml <<'TOML'
default_sched = "scx_lavd"
default_mode = "Gaming"

[scheds.scx_lavd]
gaming_mode = ["--performance"]
lowlatency_mode = ["--performance"]
auto_mode = ["--autopilot"]
powersave_mode = ["--powersave"]
server_mode = ["--autopilot"]
TOML

install -d -m 0755 /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/scx_loader.service \
  /etc/systemd/system/multi-user.target.wants/scx_loader.service

# =============================================================================
# Post-install smoke checks
# =============================================================================
echo "=== Running scx smoke checks ==="
errors=0

check_scx_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK: ${cmd}"
  else
    echo "  FAIL: ${cmd} not found" >&2
    errors=$((errors + 1))
  fi
}

check_scx_command scx_loader
check_scx_command scxctl
check_scx_command scxtui
check_scx_command scx_lavd
check_scx_command scx_bpfland
check_scx_command scx_rusty
check_scx_command scx_layered

for path in /etc/scx_loader/config.toml \
    /usr/lib/systemd/system/scx_loader.service \
    /usr/share/dbus-1/system.d/org.scx.Loader.conf \
    /usr/share/dbus-1/system-services/org.scx.Loader.service \
    /usr/share/dbus-1/interfaces/org.scx.Loader.xml \
    /usr/share/polkit-1/actions/org.scx.Loader.policy \
    /etc/systemd/system/multi-user.target.wants/scx_loader.service; do
  if [[ -e "$path" ]]; then
    echo "  OK: ${path}"
  else
    echo "  FAIL: ${path} not found" >&2
    errors=$((errors + 1))
  fi
done

# The upstream vendor config is optional (our /etc/scx_loader/config.toml
# takes precedence in the lookup order), so only check it if it was installed.
if [[ ${VENDOR_CONFIG_INSTALLED} -eq 1 ]]; then
  if [[ -e /usr/share/scx_loader/config.toml ]]; then
    echo "  OK: /usr/share/scx_loader/config.toml"
  else
    echo "  FAIL: /usr/share/scx_loader/config.toml not found" >&2
    errors=$((errors + 1))
  fi
fi

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} scx smoke check(s) failed" >&2
  exit 1
fi

# =============================================================================
# Cleanup
# =============================================================================
echo "--- Cleaning up ---"
rm -rf /tmp/scx /tmp/scx-loader /tmp/scx-cargo
clean_build_artifacts

echo "=== sched-ext/scx (${SCX_COMMIT}) + scx-loader (${SCX_LOADER_COMMIT}) built and installed successfully ==="
