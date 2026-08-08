#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building scx-manager from master ==="

install_available cmake ninja-build qt6-qtbase-devel qt6-qttools-devel

SCX_MANAGER_COMMIT=""
rm -rf /tmp/scx-manager
retry git clone --depth 1 https://github.com/CachyOS/scx-manager.git /tmp/scx-manager
SCX_MANAGER_COMMIT="$(git -C /tmp/scx-manager rev-parse --short HEAD)"
echo "scx-manager master commit: ${SCX_MANAGER_COMMIT}"

cmake -B /tmp/scx-manager/build -S /tmp/scx-manager \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
CARGO_HOME=/var/cache/apt/cargo \
  CARGO_TARGET_DIR=/var/cache/apt/target-scx-manager \
  cmake --build /tmp/scx-manager/build -j"$(nproc)"
cmake --install /tmp/scx-manager/build

echo "=== Running scx-manager smoke checks ==="
errors=0

if [[ -x /usr/bin/scx-manager ]]; then
  echo "  OK: scx-manager binary"
else
  echo "  FAIL: scx-manager binary not found" >&2
  errors=$((errors + 1))
fi
if [[ -f /usr/share/applications/org.cachyos.scx-manager.desktop ]]; then
  echo "  OK: scx-manager desktop entry"
else
  echo "  FAIL: scx-manager desktop entry not found" >&2
  errors=$((errors + 1))
fi

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} scx-manager smoke check(s) failed" >&2
  exit 1
fi

rm -rf /tmp/scx-manager
echo "=== scx-manager (${SCX_MANAGER_COMMIT}) installed successfully ==="
