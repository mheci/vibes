#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing SteamOS and Darkly themes ==="

echo "--- SteamOS presets (Valve steamdeck-kde-presets) ---"
PRESETS_VER="0.30"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/steamdeck-presets.tar.gz \
  "https://gitlab.com/evlaV/steamdeck-kde-presets/-/archive/${PRESETS_VER}/steamdeck-kde-presets-${PRESETS_VER}.tar.gz"
tar -xzf /tmp/steamdeck-presets.tar.gz -C /tmp
cp -a "/tmp/steamdeck-kde-presets-${PRESETS_VER}/usr/share/." /usr/share/
rm -rf "/tmp/steamdeck-kde-presets-${PRESETS_VER}" /tmp/steamdeck-presets.tar.gz
echo "  installed SteamOS look-and-feel, colors, icons and sounds"

echo "--- Darkly (Bali10050) ---"
DARKLY_SHA="11c27e2d98025f4d4c1598f07a185280b36f35f7"
rm -rf /tmp/darkly
install -d -m 0755 /tmp/darkly
git -C /tmp/darkly init -q
git -C /tmp/darkly remote add origin https://github.com/Bali10050/Darkly.git
retry git -C /tmp/darkly fetch -q --depth 1 origin "${DARKLY_SHA}"
git -C /tmp/darkly checkout -q FETCH_HEAD
install -d -m 0755 /usr/share/color-schemes
install -m 0644 /tmp/darkly/colors/Darkly.colors /usr/share/color-schemes/Darkly.colors
install -d -m 0755 /usr/share/plasma/desktoptheme/Darkly
cp -a /tmp/darkly/desktoptheme/dialogs /usr/share/plasma/desktoptheme/Darkly/
cp -a /tmp/darkly/desktoptheme/widgets /usr/share/plasma/desktoptheme/Darkly/
sed 's/@PROJECT_VERSION@/0.5.38/' /tmp/darkly/desktoptheme/metadata.json.in \
  >/usr/share/plasma/desktoptheme/Darkly/metadata.json
chmod 0644 /usr/share/plasma/desktoptheme/Darkly/metadata.json
rm -rf /tmp/darkly
echo "  installed Darkly desktop theme and color scheme"

echo "=== Running theme smoke checks ==="
errors=0

check_theme_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  OK: ${path}"
  else
    echo "  FAIL: ${path} not found" >&2
    errors=$((errors + 1))
  fi
}

check_theme_path /usr/share/plasma/look-and-feel/com.valve.vapor.desktop
check_theme_path /usr/share/plasma/look-and-feel/com.valve.vapor.deck.desktop
check_theme_path /usr/share/plasma/desktoptheme/Vapor
check_theme_path /usr/share/color-schemes/Darkly.colors
check_theme_path /usr/share/plasma/desktoptheme/Darkly/metadata.json

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} theme smoke check(s) failed" >&2
  exit 1
fi

echo "=== SteamOS and Darkly themes installed successfully ==="
