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

gh_asset_url() {
  local repo="$1" pattern="$2"
  python3 - "$repo" "$pattern" <<'PY'
import json, re, sys, urllib.request
repo, pattern = sys.argv[1], sys.argv[2]
req = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/releases/latest",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "vibes-bluebuild"},
)
with urllib.request.urlopen(req, timeout=60) as r:
    data = json.load(r)
rx = re.compile(pattern, re.I)
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if rx.search(name):
        print(asset["browser_download_url"])
        sys.exit(0)
print(f"No asset matching {pattern!r} in {repo} latest release", file=sys.stderr)
sys.exit(1)
PY
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

# Latest GitHub-release RPM/AppImage applications.
install_latest_rpm "anomalyco/opencode" 'opencode-desktop-linux-(amd64|x86_64).*\.rpm$' "opencode-desktop"
install_latest_rpm "Heroic-Games-Launcher/HeroicGamesLauncher" 'Heroic-.*linux.*(x86_64|x64|amd64).*\.rpm$' "heroic"
install_latest_appimage "vicinaehq/vicinae" 'Vicinae-x86_64\.AppImage$' "vicinae" "Vicinae" "Raycast-inspired launcher" "Utility;"

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

# opencode CLI latest. Installer writes the binary to /usr/local/bin through OPENCODE_INSTALL_DIR.
retry bash -c 'curl -fsSL https://opencode.ai/install | OPENCODE_INSTALL_DIR=/usr/bin bash'
if [[ -x /root/.opencode/bin/opencode && ! -x /usr/bin/opencode ]]; then
  install -Dm755 /root/.opencode/bin/opencode /usr/bin/opencode
fi

# werman RNNoise plugin release: install LADSPA plugin and keep the full bundle under /usr/local/lib/rnnoise.
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

# Smoke checks for intentionally requested critical commands/assets.
missing=0
for cmd in firefox brave-browser kitty pcmanfm-qt code zed lact scx_lavd opencode lmstudio vicinae; do
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
if [[ ! -f /usr/lib64/ladspa/librnnoise_ladspa.so ]]; then
  echo "ERROR: RNNoise LADSPA plugin missing" >&2
  exit 1
fi

"${DNF[@]}" clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
exit 0
