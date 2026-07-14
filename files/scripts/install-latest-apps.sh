#!/usr/bin/env bash
set -euo pipefail

if command -v dnf4 >/dev/null 2>&1; then
  DNF=(dnf4 -y)
elif command -v dnf >/dev/null 2>&1; then
  DNF=(dnf -y)
elif command -v dnf5 >/dev/null 2>&1; then
  DNF=(dnf5 -y)
else
  printf 'ERROR: neither dnf4, dnf, nor dnf5 is available\n' >&2
  exit 1
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

# shellcheck disable=SC2317,SC2329
on_error() {
  local exit_code=$?
  local line_no=$1
  die "install-latest-apps.sh failed at line ${line_no} with exit code ${exit_code}"
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
  if [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
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

install_latest_rpm() {
  local repo="$1" pattern="$2" name="$3"
  local rpm="/tmp/${name}.rpm"
  download_github_asset "$repo" "$pattern" "$rpm"
  retry "${DNF[@]}" install --skip-unavailable "$rpm"
  rm -f "$rpm"
}

install_latest_appimage() {
  local repo="$1" pattern="$2" binary="$3" desktop_name="$4" comment="$5" categories="${6:-Utility;}"
  local path icon_dir appimage_tmp
  appimage_tmp="/tmp/${binary}.AppImage"
  path="/usr/lib/vibes-apps/${binary}/${binary}.AppImage"
  icon_dir="/usr/share/icons/hicolor/256x256/apps"

  download_github_asset "$repo" "$pattern" "$appimage_tmp"
  install -d -m 0755 "/usr/lib/vibes-apps/${binary}" "$icon_dir" /usr/share/applications
  install -m 0755 "$appimage_tmp" "$path"
  rm -f "$appimage_tmp"

  cat >"/usr/bin/${binary}" <<EOFAPP
#!/usr/bin/env bash
exec "${path}" "\$@"
EOFAPP
  chmod 0755 "/usr/bin/${binary}"

  cat >"/usr/share/applications/${binary}.desktop" <<EOFDESKTOP
[Desktop Entry]
Name=${desktop_name}
Comment=${comment}
Exec=/usr/bin/${binary} %U
Terminal=false
Type=Application
Categories=${categories}
StartupNotify=true
EOFDESKTOP
}

install_zed() {
  install -d -m 0755 /usr/lib/zed /usr/bin /usr/share/applications /usr/share/icons/hicolor
  retry curl -fL --retry 4 --retry-delay 10 -o /tmp/zed-linux-x86_64.tar.gz \
    'https://zed.dev/api/releases/stable/latest/zed-linux-x86_64.tar.gz'
  rm -rf /tmp/zed.app
  mkdir -p /tmp/zed.app
  tar -xzf /tmp/zed-linux-x86_64.tar.gz -C /tmp/zed.app --strip-components=1
  rm -rf /usr/lib/zed/*
  cp -a /tmp/zed.app/. /usr/lib/zed/
  ln -sf /usr/lib/zed/bin/zed /usr/bin/zed
  if [[ -f /usr/lib/zed/share/applications/dev.zed.Zed.desktop ]]; then
    sed 's#Exec=zed#Exec=/usr/bin/zed#g' /usr/lib/zed/share/applications/dev.zed.Zed.desktop \
      >/usr/share/applications/dev.zed.Zed.desktop
  fi
  if [[ -d /usr/lib/zed/share/icons/hicolor ]]; then
    cp -a /usr/lib/zed/share/icons/hicolor/. /usr/share/icons/hicolor/
  fi
  rm -rf /tmp/zed.app /tmp/zed-linux-x86_64.tar.gz
}

install_lmstudio() {
  install -d -m 0755 /usr/lib/vibes-apps/lmstudio /usr/share/applications /usr/bin
  retry curl -fL --retry 4 --retry-delay 10 -o /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage \
    'https://lmstudio.ai/download/latest/linux/x64?format=AppImage'
  chmod 0755 /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage
  cat >/usr/bin/lmstudio <<'EOFLMS'
#!/usr/bin/env bash
exec /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage "$@"
EOFLMS
  chmod 0755 /usr/bin/lmstudio
  cat >/usr/share/applications/lmstudio.desktop <<'EOFDESKTOP'
[Desktop Entry]
Name=LM Studio
Comment=Local LLM management and inference
Exec=/usr/bin/lmstudio %U
Terminal=false
Type=Application
Categories=Development;Science;
StartupNotify=true
EOFDESKTOP
}

install_opencode_cli() {
  retry bash -c 'curl -fsSL https://opencode.ai/install | OPENCODE_INSTALL_DIR=/usr/bin bash'
  if [[ -x /root/.opencode/bin/opencode && ! -x /usr/bin/opencode ]]; then
    install -Dm755 /root/.opencode/bin/opencode /usr/bin/opencode
  fi
}

install_rnnoise() {
  local bundle='/tmp/linux-rnnoise.zip'
  install -d -m 0755 /usr/lib64/rnnoise /usr/lib64/ladspa
  download_github_asset 'werman/noise-suppression-for-voice' 'linux-rnnoise\.zip$' "$bundle"
  rm -rf /tmp/linux-rnnoise
  unzip -q "$bundle" -d /tmp/linux-rnnoise
  cp -a /tmp/linux-rnnoise/. /usr/lib64/rnnoise/

  local ladspa_so
  ladspa_so="$(find /tmp/linux-rnnoise -type f -name 'librnnoise_ladspa.so' | head -n1)"
  [[ -n "$ladspa_so" ]] || die 'librnnoise_ladspa.so not found in RNNoise bundle'
  install -Dm755 "$ladspa_so" /usr/lib64/ladspa/librnnoise_ladspa.so

  rm -rf /tmp/linux-rnnoise "$bundle"
}

install_bpftune() {
  log 'Building and installing latest bpftune from upstream'
  rm -rf /tmp/bpftune
  retry git clone --depth 1 https://github.com/oracle/bpftune.git /tmp/bpftune
  if rpm -q kernel-headers >/dev/null 2>&1 || "${DNF[@]}" repoquery --available kernel-headers >/dev/null 2>&1; then
    retry "${DNF[@]}" install kernel-headers
  fi
  if rpm -q kernel-devel >/dev/null 2>&1 || "${DNF[@]}" repoquery --available kernel-devel >/dev/null 2>&1; then
    retry "${DNF[@]}" install kernel-devel
  fi
  make -C /tmp/bpftune -j"$(nproc)"
  make -C /tmp/bpftune install
  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
  fi
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  if [[ -f /usr/lib/systemd/system/bpftune.service ]]; then
    ln -sf /usr/lib/systemd/system/bpftune.service /etc/systemd/system/multi-user.target.wants/bpftune.service
  elif [[ -f /lib/systemd/system/bpftune.service ]]; then
    ln -sf /lib/systemd/system/bpftune.service /etc/systemd/system/multi-user.target.wants/bpftune.service
  else
    die 'bpftune.service was not installed'
  fi
  rm -rf /tmp/bpftune
}

assert_commands_present() {
  local missing=0 cmd
  local required=(
    bpftune
    code
    heroic
    kitty
    lmstudio
    opencode
    scx_lavd
    vicinae
    zed
  )

  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "required command missing after install: $cmd"
      missing=1
    fi
  done

  if ! command -v steam >/dev/null 2>&1; then
    warn 'steam command missing after install'
    missing=1
  fi

  (( missing == 0 )) || die 'one or more required applications were not installed correctly'
}

install_zed
install_latest_rpm 'anomalyco/opencode' 'opencode-desktop-linux-x86_64\.rpm$' 'opencode-desktop'
install_latest_rpm 'Heroic-Games-Launcher/HeroicGamesLauncher' 'Heroic-.*linux.*x86_64.*\.rpm$' 'heroic'
install_lmstudio
install_latest_appimage 'vicinaehq/vicinae' 'Vicinae.*x86_64\.AppImage$' 'vicinae' 'Vicinae' 'Raycast-inspired launcher' 'Utility;'
install_opencode_cli
install_rnnoise
install_bpftune
assert_commands_present

"${DNF[@]}" clean all
rm -rf /var/cache/dnf /var/cache/libdnf5
exit 0
