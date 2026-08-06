#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building Klassy from master ==="

install_available cmake ninja-build extra-cmake-modules gettext
retry "${DNF[@]}" install --skip-unavailable --skip-broken \
  "cmake(ECM)" \
  "cmake(Qt6Core)" "cmake(Qt6DBus)" "cmake(Qt6Quick)" "cmake(Qt6Svg)" \
  "cmake(Qt6Widgets)" "cmake(Qt6Xml)" \
  "cmake(KF6Config)" "cmake(KF6CoreAddons)" "cmake(KF6GuiAddons)" \
  "cmake(KF6I18n)" "cmake(KF6KCMUtils)" "cmake(KF6WindowSystem)" \
  "cmake(KF6ColorScheme)" "cmake(KF6FrameworkIntegration)" \
  "cmake(KF6KirigamiPlatform)" "cmake(KF6IconThemes)" "cmake(KF6Package)" \
  "cmake(KF6Service)" "cmake(KF6WidgetsAddons)" "cmake(KF6Notifications)" \
  "cmake(KDecoration3)" || true

KLASSY_COMMIT=""
rm -rf /tmp/klassy
retry git clone --depth 1 https://github.com/ekaaty/klassy.git /tmp/klassy
KLASSY_COMMIT="$(git -C /tmp/klassy rev-parse --short HEAD)"
echo "klassy master commit: ${KLASSY_COMMIT}"

cmake -B /tmp/klassy/build -S /tmp/klassy \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF
cmake --build /tmp/klassy/build -j"$(nproc)"
cmake --install /tmp/klassy/build

echo "=== Running Klassy smoke checks ==="
errors=0

klassy_plugin="$(find /usr/lib64/qt6/plugins /usr/lib/qt6/plugins \
  -type f -name '*klassy*' 2>/dev/null | head -n1)"
if [[ -n "${klassy_plugin}" ]]; then
  echo "  OK: ${klassy_plugin}"
else
  echo "  FAIL: klassy plugin not found" >&2
  errors=$((errors + 1))
fi
if [[ -d /usr/share/themes/Klassy || -d /usr/share/aurorae/themes/Klassy || \
    -n "$(find /usr/share -maxdepth 4 -iname '*klassy*' 2>/dev/null | head -n1)" ]]; then
  echo "  OK: klassy themes installed"
else
  echo "  FAIL: klassy themes not installed" >&2
  errors=$((errors + 1))
fi

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} klassy smoke check(s) failed" >&2
  exit 1
fi

rm -rf /tmp/klassy
echo "=== Klassy (${KLASSY_COMMIT}) installed successfully ==="
