#!/usr/bin/env bash
set -euo pipefail

if command -v dnf5 >/dev/null 2>&1; then
  DNF=(dnf5 -y)
else
  DNF=(dnf -y)
fi

retry() {
  local attempts=4 delay=10 n=1
  until "$@"; do
    if (( n >= attempts )); then
      echo "ERROR: command failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    echo "WARN: command failed, retrying in ${delay}s: $*" >&2
    sleep "$delay"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

# Use curl + jq to fetch latest release asset URLs from GitHub.
# Avoids Python heredocs which can break in restricted BlueBuild container envs.
gh_asset_url() {
  local repo="$1" pattern="$2"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: vibes-bluebuild")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  elif [[ -n "${GH_PAT:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GH_PAT}")
  fi
  local assets_json
  assets_json="$(curl -sSL "${headers[@]}" "$api_url" | jq -c '.assets // []')"
  if [[ -z "$assets_json" || "$assets_json" == "null" ]]; then
    echo "ERROR: failed to fetch release assets for ${repo}" >&2
    return 1
  fi
  local url
  url="$(echo "$assets_json" | jq -r --arg pattern "$pattern" '[.[] | select(.name | test($pattern; "i"))] | first | .browser_download_url // empty')"
  if [[ -z "$url" ]]; then
    echo "ERROR: no asset matching pattern '${pattern}' in ${repo} latest release" >&2
    return 1
  fi
  echo "$url"
}

install_latest_rpm() {
  local repo="$1" pattern="$2" name="$3"
  local url rpm
  url="$(gh_asset_url "$repo" "$pattern")"
  rpm="/tmp/${name}.rpm"
  echo "Installing latest ${name} RPM from ${url}"
  retry curl -fL --retry 4 --retry-delay 10 -o "$rpm" "$url"
  retry "${DNF[@]}" install --skip-unavailable "$rpm"
  rm -f "$rpm"
}

install_latest_appimage() {
  local repo="$1" pattern="$2" binary="$3" desktop_name="$4" comment="$5" categories="${6:-Utility;}"
  local url path icon_dir
  url="$(gh_asset_url "$repo" "$pattern")"
  path="/usr/lib/vibes-apps/${binary}/${binary}.AppImage"
  icon_dir="/usr/share/icons/hicolor/256x256/apps"
  echo "Installing latest ${desktop_name} AppImage from ${url}"
  install -d -m 0755 "/usr/lib/vibes-apps/${binary}" "$icon_dir" /usr/share/applications
  retry curl -fL --retry 4 --retry-delay 10 -o "$path" "$url"
  chmod 0755 "$path"
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

# Zed latest official Linux tarball.
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

# Latest GitHub-release RPM applications.
install_latest_rpm "anomalyco/opencode" 'opencode-desktop-linux-x86_64\.rpm$' "opencode-desktop"
install_latest_rpm "Heroic-Games-Launcher/HeroicGamesLauncher" 'Heroic-.*linux.*x86_64.*\.rpm$' "heroic"

# LM Studio latest official AppImage.
install -d -m 0755 /usr/lib/vibes-apps/lmstudio /usr/share/applications /usr/bin
retry curl -fL --retry 4 --retry-delay 10 -o /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage 'https://lmstudio.ai/download/latest/linux/x64?format=AppImage'
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

# Vicinae AppImage (RPM excluded on Bazzite due to mesa-libEGL dependency conflict).
install_latest_appimage "vicinaehq/vicinae" 'Vicinae-x86_64\.AppImage$' "vicinae" "Vicinae" "Raycast-inspired launcher" "Utility;"

# opencode CLI latest. Installer writes the binary to /usr/local/bin through OPENCODE_INSTALL_DIR.
retry bash -c 'curl -fsSL https://opencode.ai/install | OPENCODE_INSTALL_DIR=/usr/bin bash'
if [[ -x /root/.opencode/bin/opencode && ! -x /usr/bin/opencode ]]; then
  install -Dm755 /root/.opencode/bin/opencode /usr/bin/opencode
fi

# werman RNNoise plugin release: install LADSPA plugin and keep the full bundle under /usr/lib64/rnnoise.
install -d -m 0755 /usr/lib64/rnnoise /usr/lib64/ladspa
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/linux-rnnoise.zip \
  "$(gh_asset_url "werman/noise-suppression-for-voice" 'linux-rnnoise\.zip$')"
rm -rf /tmp/linux-rnnoise
unzip -q /tmp/linux-rnnoise.zip -d /tmp/linux-rnnoise
cp -a /tmp/linux-rnnoise/. /usr/lib64/rnnoise/
ladspa_so="$(find /tmp/linux-rnnoise -type f -name 'librnnoise_ladspa.so' | head -n1 || true)"
if [[ -z "${ladspa_so}" ]]; then
  echo "ERROR: librnnoise_ladspa.so not found in linux-rnnoise.zip" >&2
  exit 1
fi
install -Dm755 "${ladspa_so}" /usr/lib64/ladspa/librnnoise_ladspa.so
rm -rf /tmp/linux-rnnoise /tmp/linux-rnnoise.zip

# bpftune latest from upstream. Build from source since Fedora packages are inconsistent.
echo "Building and installing latest bpftune from upstream"
rm -rf /tmp/bpftune
retry git clone --depth 1 https://github.com/oracle/bpftune.git /tmp/bpftune
# Ensure kernel headers are present for the build.
"${DNF[@]}" install --skip-unavailable kernel-headers kernel-devel || true
make -C /tmp/bpftune -j"$(nproc)"
make -C /tmp/bpftune install
ldconfig || true
install -d -m 0755 /etc/systemd/system/multi-user.target.wants
if [[ -f /usr/lib/systemd/system/bpftune.service ]]; then
  ln -sf /usr/lib/systemd/system/bpftune.service /etc/systemd/system/multi-user.target.wants/bpftune.service
elif [[ -f /lib/systemd/system/bpftune.service ]]; then
  ln -sf /lib/systemd/system/bpftune.service /etc/systemd/system/multi-user.target.wants/bpftune.service
fi
rm -rf /tmp/bpftune

# Smoke checks for intentionally requested critical commands/assets.
missing=0
for cmd in kitty pcmanfm-qt code zed lact scx_lavd opencode lmstudio vicinae; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "WARN: requested command not found after install: $cmd" >&2
    missing=1
  fi
done
# Heroic command names vary by package; accept either.
if ! command -v heroic >/dev/null 2>&1 && ! command -v heroic-games-launcher >/dev/null 2>&1; then
  echo "WARN: Heroic launcher command not found after install" >&2
  missing=1
fi
if [[ "$missing" -ne 0 ]]; then
  echo "WARN: one or more non-fatal application smoke checks reported missing commands" >&2
fi
if ! command -v bpftune >/dev/null 2>&1 && [[ ! -x /usr/sbin/bpftune ]]; then
  echo "ERROR: bpftune missing after build" >&2
  exit 1
fi
if [[ ! -e /etc/systemd/system/multi-user.target.wants/bpftune.service ]]; then
  echo "ERROR: bpftune service is not enabled" >&2
  exit 1
fi
if [[ ! -f /usr/lib64/ladspa/librnnoise_ladspa.so ]]; then
  echo "ERROR: RNNoise LADSPA plugin missing" >&2
  exit 1
fi

"${DNF[@]}" clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
exit 0
