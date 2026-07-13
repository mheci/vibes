#!/usr/bin/env bash
set -euo pipefail

if command -v dnf5 >/dev/null 2>&1; then
  DNF=(dnf5 -y)
else
  DNF=(dnf -y)
fi

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  local line_no=$1
  die "install-themes-and-assets.sh failed at line ${line_no} with exit code ${exit_code}"
}
trap 'on_error $LINENO' ERR

retry() {
  local attempts=4 delay=10 n=1
  until "$@"; do
    if (( n >= attempts )); then
      printf 'ERROR: command failed after %d attempts: %s\n' "$attempts" "$*" >&2
      return 1
    fi
    printf 'WARN: command failed, retrying in %ss: %s\n' "$delay" "$*" >&2
    sleep "$delay"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

github_headers() {
  local headers=(-H 'Accept: application/vnd.github+json' -H 'User-Agent: vibes-bluebuild')
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  elif [[ -n "${GH_PAT:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GH_PAT}")
  fi
  printf '%s\n' "${headers[@]}"
}

github_api_get() {
  local url="$1"
  local header_array=()
  mapfile -t header_array < <(github_headers)
  retry curl -fsSL "${header_array[@]}" "$url"
}

github_latest_release_json() {
  local repo="$1"
  github_api_get "https://api.github.com/repos/${repo}/releases/latest"
}

github_asset_json() {
  local repo="$1" pattern="$2"
  github_latest_release_json "$repo" | jq -r --arg pattern "$pattern" '
    [.assets[]? | select(.name | test($pattern; "i"))] | first // empty
  '
}

download_github_asset() {
  local repo="$1" pattern="$2" output="$3"
  local asset_json url digest algo expected

  asset_json="$(github_asset_json "$repo" "$pattern")"
  [[ -n "$asset_json" && "$asset_json" != "null" ]] || die "no release asset matching '${pattern}' found for ${repo}"

  url="$(jq -r '.browser_download_url // empty' <<<"$asset_json")"
  digest="$(jq -r '.digest // empty' <<<"$asset_json")"
  [[ -n "$url" ]] || die "release asset for ${repo} does not expose a download URL"

  log "Downloading ${repo} asset ${url}"
  retry curl -fL --retry 4 --retry-delay 10 -o "$output" "$url"

  if [[ -n "$digest" ]]; then
    algo="${digest%%:*}"
    expected="${digest#*:}"
    case "$algo" in
      sha256)
        printf '%s  %s\n' "$expected" "$output" | sha256sum -c -
        ;;
      sha512)
        printf '%s  %s\n' "$expected" "$output" | sha512sum -c -
        ;;
      *)
        warn "unsupported digest algorithm '${algo}' for ${repo} asset verification"
        ;;
    esac
  fi
}

git_clone_latest() {
  local repo="$1" dest="$2"
  rm -rf "$dest"
  retry git clone --depth 1 "https://github.com/${repo}.git" "$dest"
}

copy_repo_tree() {
  local src="$1" dest="$2"
  install -d -m 0755 "$dest"
  cp -a "$src"/. "$dest/"
}

install_darkly() {
  local fedora_release url rpm_file src_dir build_dir
  fedora_release="$(rpm -E %fedora)"
  url="$(github_asset_json 'Bali10050/Darkly' "darkly-.*\\.fc${fedora_release}\\.x86_64\\.rpm$")"

  if [[ -n "$url" && "$url" != "null" ]]; then
    rpm_file="/tmp/darkly-${fedora_release}.rpm"
    download_github_asset 'Bali10050/Darkly' "darkly-.*\.fc${fedora_release}\.x86_64\.rpm$" "$rpm_file"
    retry "${DNF[@]}" install --skip-unavailable "$rpm_file"
    rm -f "$rpm_file"
    return 0
  fi

  warn "no Fedora ${fedora_release} Darkly RPM release asset found, building Darkly from source"
  src_dir="/tmp/Darkly"
  build_dir="${src_dir}/build"
  git_clone_latest 'Bali10050/Darkly' "$src_dir"
  cmake -B "$build_dir" -S "$src_dir" -DBUILD_TESTING=OFF -Wno-dev -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
  cmake --build "$build_dir" -j"$(nproc)"
  cmake --install "$build_dir"
  rm -rf "$src_dir"
}

install_darkly_gtk() {
  local src_dir='/tmp/darkly-gtk'
  git_clone_latest 'wrymt/darkly-gtk' "$src_dir"
  (cd "$src_dir" && bash ./install.sh -d /usr/share/themes)
  rm -rf "$src_dir"
}

install_beauty_plasma_themes() {
  local src_dir='/tmp/Beauty-Plasma-Themes'
  git_clone_latest 'L4ki/Beauty-Plasma-Themes' "$src_dir"
  copy_repo_tree "$src_dir/Beauty Global Themes" /usr/share/plasma/look-and-feel
  copy_repo_tree "$src_dir/Beauty Plasma Themes" /usr/share/plasma/desktoptheme
  copy_repo_tree "$src_dir/Beauty Color Schemes" /usr/share/color-schemes
  copy_repo_tree "$src_dir/Beauty Window Decorations" /usr/share/aurorae/themes
  if [[ -d "$src_dir/Beauty Wallpapers" ]]; then
    copy_repo_tree "$src_dir/Beauty Wallpapers" /usr/share/wallpapers
  fi
  rm -rf "$src_dir"
}

install_macos_tahoe_theme_bundle() {
  local src_dir='/tmp/macOsTahoeKdeTheme'
  local cursor_dir cursor_theme f target

  git_clone_latest 'ddc/macOsTahoeKdeTheme' "$src_dir"
  copy_repo_tree "$src_dir/plasma/look-and-feel" /usr/share/plasma/look-and-feel
  copy_repo_tree "$src_dir/plasma/desktoptheme" /usr/share/plasma/desktoptheme
  copy_repo_tree "$src_dir/aurorae/themes" /usr/share/aurorae/themes
  copy_repo_tree "$src_dir/color-schemes" /usr/share/color-schemes
  copy_repo_tree "$src_dir/kvantum" /usr/share/Kvantum
  copy_repo_tree "$src_dir/icons" /usr/share/icons
  copy_repo_tree "$src_dir/cursors" /usr/share/icons
  copy_repo_tree "$src_dir/gtk/themes" /usr/share/themes
  copy_repo_tree "$src_dir/sounds" /usr/share/sounds

  for cursor_theme in \
    DDCmacOsTahoe-cursor-dark \
    DDCmacOsTahoe-cursor-white \
    DDCmacOsTahoe-cursor-mixed \
    DDCmacOsMonterey-cursor-white; do
    cursor_dir="/usr/share/icons/${cursor_theme}/cursors"
    if [[ -d "$cursor_dir" ]]; then
      for f in "$cursor_dir"/*; do
        if [[ -f "$f" ]] && file "$f" | grep -q 'ASCII text'; then
          target="$(cat "$f")"
          rm -f "$f"
          ln -sf "$target" "$f"
        fi
      done
      if [[ -e "$cursor_dir/size_hor" && ! -e "$cursor_dir/col-resize" ]]; then
        ln -sf size_hor "$cursor_dir/col-resize"
      fi
    fi
  done

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/DDCmacOsTahoe-icons-dark
  fi
  rm -rf "$src_dir"
}

install_whitesur_kde() {
  local src_dir='/tmp/WhiteSur-kde'
  git_clone_latest 'vinceliuice/WhiteSur-kde' "$src_dir"
  (cd "$src_dir" && bash ./install.sh)
  rm -rf "$src_dir"
}

install_mcmojave_kde() {
  local src_dir='/tmp/McMojave-kde'
  git_clone_latest 'vinceliuice/McMojave-kde' "$src_dir"
  (cd "$src_dir" && bash ./install.sh)
  rm -rf "$src_dir"
}

install_whitesur_cursors() {
  local src_dir='/tmp/WhiteSur-cursors'
  git_clone_latest 'vinceliuice/WhiteSur-cursors' "$src_dir"
  (cd "$src_dir" && bash ./install.sh)
  rm -rf "$src_dir"
}

install_whitesur_icons() {
  local src_dir='/tmp/WhiteSur-icon-theme'
  git_clone_latest 'vinceliuice/WhiteSur-icon-theme' "$src_dir"
  (cd "$src_dir" && bash ./install.sh -d /usr/share/icons -p)
  rm -rf "$src_dir"
}

write_theme_manifest() {
  install -d -m 0755 /usr/share/vibes
  cat >/usr/share/vibes/themes-manifest.txt <<'EOF'
Installed theme bundles:
- Darkly Qt application style
- Darkly GTK theme
- Beauty Plasma Themes (global themes, plasma themes, color schemes, aurorae, wallpapers)
- macOsTahoeKdeTheme bundle (look-and-feel, plasma, aurorae, kvantum, icons, cursors, gtk, sounds)
- WhiteSur KDE theme bundle
- McMojave KDE theme bundle
- WhiteSur cursor theme
- WhiteSur icon theme
EOF
}

smoke_check_theme_assets() {
  local required_paths=(
    /usr/share/themes/Darkly
    /usr/share/plasma/look-and-feel/Beauty-Color-Global-6
    /usr/share/plasma/look-and-feel/com.github.ddc.DDCmacOsTahoe-dark
    /usr/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur
    /usr/share/plasma/look-and-feel/com.github.vinceliuice.McMojave
    /usr/share/icons/DDCmacOsTahoe-cursor-dark
    /usr/share/icons/DDCmacOsTahoe-cursor-mixed
    /usr/share/icons/DDCmacOsTahoe-cursor-white
    /usr/share/icons/DDCmacOsMonterey-cursor-white
    /usr/share/icons/WhiteSur
    /usr/share/icons/WhiteSur-cursors
    /usr/share/vibes/themes-manifest.txt
  )

  local path
  for path in "${required_paths[@]}"; do
    [[ -e "$path" ]] || die "expected theme asset missing: $path"
  done
}

install_darkly
install_darkly_gtk
install_beauty_plasma_themes
install_macos_tahoe_theme_bundle
install_whitesur_kde
install_mcmojave_kde
install_whitesur_cursors
install_whitesur_icons
write_theme_manifest
smoke_check_theme_assets

"${DNF[@]}" clean all
rm -rf /var/cache/dnf /var/cache/libdnf5 /tmp/Darkly /tmp/darkly-gtk /tmp/Beauty-Plasma-Themes /tmp/macOsTahoeKdeTheme /tmp/WhiteSur-kde /tmp/McMojave-kde /tmp/WhiteSur-cursors /tmp/WhiteSur-icon-theme
