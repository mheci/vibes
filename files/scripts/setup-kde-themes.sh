#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing KDE themes, color schemes, icons and sounds ==="

install_available papirus-icon-theme

clone_pinned() {
  local url="$1" sha="$2" dir="$3"
  rm -rf "${dir}"
  install -d -m 0755 "${dir}"
  git -C "${dir}" init -q
  git -C "${dir}" remote add origin "${url}"
  retry git -C "${dir}" fetch -q --depth 1 origin "${sha}"
  git -C "${dir}" checkout -q FETCH_HEAD
}

copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -d "${src}" ]] && [[ -n "$(ls -A "${src}" 2>/dev/null)" ]]; then
    install -d -m 0755 "${dst}"
    cp -a "${src}/." "${dst}/"
    echo "  installed $(basename "${src}") -> ${dst}"
  fi
}

install_kde_theme_repo() {
  local name="$1" url="$2" sha="$3"
  local dir="/tmp/theme-${name}"
  echo "--- ${name} ---"
  clone_pinned "${url}" "${sha}" "${dir}"
  copy_if_exists "${dir}/aurorae" /usr/share/aurorae/themes
  copy_if_exists "${dir}/color-schemes" /usr/share/color-schemes
  copy_if_exists "${dir}/colors" /usr/share/color-schemes
  copy_if_exists "${dir}/look-and-feel" /usr/share/plasma/look-and-feel
  copy_if_exists "${dir}/plasma" /usr/share/plasma
  copy_if_exists "${dir}/desktoptheme" /usr/share/plasma/desktoptheme
  copy_if_exists "${dir}/kdecoration" /usr/share/aurorae/themes
  copy_if_exists "${dir}/wallpapers" /usr/share/wallpapers
  copy_if_exists "${dir}/wallpaper" /usr/share/wallpapers
  copy_if_exists "${dir}/kvantum" /usr/share/Kvantum
  copy_if_exists "${dir}/konsole" /usr/share/konsole
  copy_if_exists "${dir}/sddm" /usr/share/sddm/themes
  rm -rf "${dir}"
}

install_icon_repo() {
  local name="$1" url="$2" sha="$3"
  local dir="/tmp/theme-${name}"
  echo "--- ${name} (icons) ---"
  clone_pinned "${url}" "${sha}" "${dir}"
  (
    cd "${dir}"
    ./install.sh -d /usr/share/icons ${4:+-t $4}
  )
  rm -rf "${dir}"
}

echo "--- SteamOS presets (Valve steamdeck-kde-presets) ---"
PRESETS_VER="0.30"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/steamdeck-presets.tar.gz \
  "https://gitlab.com/evlaV/steamdeck-kde-presets/-/archive/${PRESETS_VER}/steamdeck-kde-presets-${PRESETS_VER}.tar.gz"
tar -xzf /tmp/steamdeck-presets.tar.gz -C /tmp
cp -a "/tmp/steamdeck-kde-presets-${PRESETS_VER}/usr/share/." /usr/share/
rm -rf "/tmp/steamdeck-kde-presets-${PRESETS_VER}" /tmp/steamdeck-presets.tar.gz
echo "  installed SteamOS look-and-feel, colors, icons and sounds"

install_kde_theme_repo "marge" \
  "https://gitlab.com/jomada/marge.git" \
  "c580d08371773682be434bf8488d51c83df96211"

install_kde_theme_repo "scratchy" \
  "https://gitlab.com/jomada/Scratchy.git" \
  "9eb375276ef5e4dedc42ac0f76f12e63455785b5"

install_kde_theme_repo "graphite" \
  "https://github.com/vinceliuice/Graphite-kde-theme.git" \
  "09665ba967475da01ad9ec2a5a5822f15ba14e84"

install_kde_theme_repo "whitesur" \
  "https://github.com/vinceliuice/WhiteSur-kde.git" \
  "1e4d960945572d05a3d96bec5253dd83971239f2"

install_kde_theme_repo "mcmojave" \
  "https://github.com/vinceliuice/McMojave-kde.git" \
  "a1745e9c35d57c6db7e298180dba53ac4a70fee9"

echo "--- Darkly (desktop theme, colors, decoration) ---"
DARKLY_DIR="/tmp/theme-darkly"
clone_pinned "https://github.com/Bali10050/Darkly.git" \
  "11c27e2d98025f4d4c1598f07a185280b36f35f7" "${DARKLY_DIR}"
copy_if_exists "${DARKLY_DIR}/colors" /usr/share/color-schemes
copy_if_exists "${DARKLY_DIR}/kdecoration" /usr/share/aurorae/themes
if [[ -d "${DARKLY_DIR}/desktoptheme" ]]; then
  install -d -m 0755 /usr/share/plasma/desktoptheme/Darkly
  cp -a "${DARKLY_DIR}/desktoptheme/." /usr/share/plasma/desktoptheme/Darkly/
  echo "  installed Darkly desktop theme"
fi
rm -rf "${DARKLY_DIR}"

echo "--- BonaFides Plasma Themes ---"
BONA_DIR="/tmp/theme-bonafides"
clone_pinned "https://github.com/L4ki/BonaFides-Plasma-Themes.git" \
  "97d4fe35e5c6d925b9f723f5411a42880fe41298" "${BONA_DIR}"
copy_if_exists "${BONA_DIR}/BonaFides Global Themes" /usr/share/plasma/look-and-feel
copy_if_exists "${BONA_DIR}/BonaFides Plasma Themes" /usr/share/plasma/desktoptheme
copy_if_exists "${BONA_DIR}/BonaFides Color Schemes" /usr/share/color-schemes
copy_if_exists "${BONA_DIR}/BonaFides Window Decorations" /usr/share/aurorae/themes
copy_if_exists "${BONA_DIR}/BonaFides Splashscreen" /usr/share/plasma/splashscreens
copy_if_exists "${BONA_DIR}/BonaFides Wallpapers" /usr/share/wallpapers
copy_if_exists "${BONA_DIR}/BonaFides Kvantum Themes" /usr/share/Kvantum
copy_if_exists "${BONA_DIR}/BonaFides Konsole Color Schmes" /usr/share/konsole
copy_if_exists "${BONA_DIR}/BonaFides GTK Themes" /usr/share/themes
rm -rf "${BONA_DIR}"

install_icon_repo "tela-circle" \
  "https://github.com/vinceliuice/Tela-circle-icon-theme.git" \
  "c0adf1ab92f564e3b83540441921f26d121b09c3"

install_icon_repo "whitesur-icons" \
  "https://github.com/vinceliuice/WhiteSur-icon-theme.git" \
  "c5c8ee5588cf8640dbe25838fa62b43c81c45a33" "all"

echo "--- macOS Big Sur sound scheme ---"
SOUND_DIR="/tmp/theme-sounds"
clone_pinned "https://github.com/gxanshu/macos-bigsur-sound-theme-linux.git" \
  "88275891dc8ce9c14f69431eddbb3d04d5069e53" "${SOUND_DIR}"
install -d -m 0755 /usr/share/sounds/macOS-BigSur
if [[ -d "${SOUND_DIR}/theme/bigsur" ]]; then
  cp -a "${SOUND_DIR}/theme/bigsur/." /usr/share/sounds/macOS-BigSur/
  echo "  installed macOS Big Sur sound scheme"
else
  cp -a "${SOUND_DIR}/sounds/." /usr/share/sounds/macOS-BigSur/
fi
rm -rf "${SOUND_DIR}"

fc-cache -f >/dev/null 2>&1 || true

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
check_theme_path /usr/share/plasma/look-and-feel/Marge
check_theme_path /usr/share/plasma/look-and-feel/Scratchy
check_theme_path /usr/share/plasma/desktoptheme/Darkly
check_theme_path /usr/share/plasma/desktoptheme/Graphite
check_theme_path /usr/share/plasma/desktoptheme/WhiteSur
check_theme_path /usr/share/plasma/desktoptheme/McMojave
check_theme_path /usr/share/color-schemes
if find /usr/share/color-schemes -maxdepth 1 -name '*.colors' | grep -q .; then
  echo "  OK: color schemes present"
else
  echo "  FAIL: no color schemes installed" >&2
  errors=$((errors + 1))
fi
if find /usr/share/icons -maxdepth 1 -type d -name 'Tela-circle*' | grep -q .; then
  echo "  OK: Tela-circle icon themes"
else
  echo "  FAIL: Tela-circle icon themes missing" >&2
  errors=$((errors + 1))
fi
if [[ -d /usr/share/icons/WhiteSur || -d /usr/share/icons/WhiteSur-dark ]]; then
  echo "  OK: WhiteSur icon themes"
else
  echo "  FAIL: WhiteSur icon themes missing" >&2
  errors=$((errors + 1))
fi
if rpm -q papirus-icon-theme >/dev/null 2>&1; then
  echo "  OK: papirus-icon-theme (rpm)"
else
  echo "  FAIL: papirus-icon-theme not installed" >&2
  errors=$((errors + 1))
fi
check_theme_path /usr/share/sounds/macOS-BigSur/index.theme

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} theme smoke check(s) failed" >&2
  exit 1
fi

echo "=== KDE themes installed successfully ==="
