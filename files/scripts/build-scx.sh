#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building latest sched-ext/scx from source ==="

echo "--- Installing scx build dependencies ---"

install_available \
  cargo rust clang lld llvm bpftool \
  elfutils-libelf-devel libbpf-devel protobuf-compiler libseccomp-devel \
  jq jq-devel zlib openssl-devel

echo "--- Removing COPR scx packages ---"

for pkg in scx-scheds scx-tools-git; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    rpm -e --nodeps "${pkg}" || true
  fi
done

echo "--- Cloning sched-ext/scx (v1.1.2) ---"

SCX_TAG="v1.1.2"
SCX_COMMIT=""
rm -rf /tmp/scx /tmp/scx-cargo
retry git clone --depth 1 --branch "${SCX_TAG}" \
  https://github.com/sched-ext/scx.git /tmp/scx
SCX_COMMIT="$(git -C /tmp/scx rev-parse --short HEAD)"
echo "scx tag: ${SCX_TAG} (${SCX_COMMIT})"

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
find target/release -maxdepth 1 -type f -executable ! -name '*.so' \
  -exec install -Dm755 -t /usr/bin {} +

echo "--- Building scx_loader/scxctl/scxtui (sched-ext/scx-loader) ---"

SCX_LOADER_TAG="v1.1.2"
SCX_LOADER_COMMIT=""
rm -rf /tmp/scx-loader
retry git clone --depth 1 --branch "${SCX_LOADER_TAG}" \
  https://github.com/sched-ext/scx-loader.git /tmp/scx-loader
SCX_LOADER_COMMIT="$(git -C /tmp/scx-loader rev-parse --short HEAD)"
echo "scx-loader tag: ${SCX_LOADER_TAG} (${SCX_LOADER_COMMIT})"

cd /tmp/scx-loader
retry cargo build --release

echo "--- Installing scx_loader toolchain ---"
find target/release -maxdepth 1 -type f -executable ! -name '*.so' \
  -exec install -Dm755 -t /usr/bin {} +

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

echo "--- Cleaning up ---"
rm -rf /tmp/scx /tmp/scx-loader /tmp/scx-cargo
clean_build_artifacts

echo "=== sched-ext/scx (${SCX_COMMIT}) + scx-loader (${SCX_LOADER_COMMIT}) built and installed successfully ==="
