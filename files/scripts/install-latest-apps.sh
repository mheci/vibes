#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Latest Applications ==="

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

# Fetch the latest GitHub release asset URL matching a pattern.
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

# --- Zed Editor (latest stable from zed.dev) ---
echo "Installing Zed Editor..."
install -d -m 0755 /usr/lib/zed
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

# --- GitHub-release RPM applications ---
install_latest_rpm "anomalyco/opencode" 'opencode-desktop-linux-x86_64\.rpm$' "opencode-desktop"
install_latest_rpm "Heroic-Games-Launcher/HeroicGamesLauncher" 'Heroic-.*linux.*x86_64.*\.rpm$' "heroic"

# --- LM Studio (latest official AppImage) ---
echo "Installing LM Studio..."
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

# --- Vicinae (AppImage; RPM excluded on Bazzite due to mesa-libEGL dependency conflict) ---
install_latest_appimage "vicinaehq/vicinae" 'Vicinae-x86_64\.AppImage$' "vicinae" "Vicinae" "Raycast-inspired launcher" "Utility;"

# --- opencode CLI ---
echo "Installing opencode CLI..."
retry bash -c 'curl -fsSL https://opencode.ai/install | OPENCODE_INSTALL_DIR=/usr/bin bash' || true
if [[ -x /root/.opencode/bin/opencode && ! -x /usr/bin/opencode ]]; then
  install -Dm755 /root/.opencode/bin/opencode /usr/bin/opencode || true
fi

# --- RNNoise LADSPA plugin (audio noise suppression) ---
echo "Installing RNNoise LADSPA plugin..."
install -d -m 0755 /usr/lib64/rnnoise /usr/lib64/ladspa
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/linux-rnnoise.zip \
  "$(gh_asset_url "werman/noise-suppression-for-voice" 'linux-rnnoise\.zip$')"
rm -rf /tmp/linux-rnnoise
unzip -q /tmp/linux-rnnoise.zip -d /tmp/linux-rnnoise
cp -a /tmp/linux-rnnoise/. /usr/lib64/rnnoise/
ladspa_so="$(find /tmp/linux-rnnoise -type f -name 'librnnoise_ladspa.so' | head -n1)"
if [[ -z "${ladspa_so}" ]]; then
  echo "ERROR: librnnoise_ladspa.so not found in linux-rnnoise.zip" >&2
  exit 1
fi
install -Dm755 "${ladspa_so}" /usr/lib64/ladspa/librnnoise_ladspa.so
rm -rf /tmp/linux-rnnoise /tmp/linux-rnnoise.zip

# --- bpftune (BPF-based auto-tuning daemon) ---
echo "Building and installing bpftune from upstream..."
"${DNF[@]}" install --skip-unavailable kernel-headers kernel-devel gcc make libbpf libbpf-devel libcap libcap-devel libnl3 libnl3-devel python3-docutils elfutils-libelf-devel pkgconf-pkg-config zlib-devel

rm -rf /tmp/bpftune
retry git clone --depth 1 https://github.com/oracle/bpftune.git /tmp/bpftune
make -C /tmp/bpftune -j"$(nproc)"
make -C /tmp/bpftune install
ldconfig || true

# Enable bpftune service
install -d -m 0755 /etc/systemd/system/multi-user.target.wants
bpftune_service=""
for candidate in /usr/lib/systemd/system/bpftune.service /lib/systemd/system/bpftune.service; do
  if [[ -f "$candidate" ]]; then
    bpftune_service="$candidate"
    break
  fi
done
if [[ -n "$bpftune_service" ]]; then
  ln -sf "$bpftune_service" /etc/systemd/system/multi-user.target.wants/bpftune.service
else
  echo "ERROR: bpftune.service unit file not found after install" >&2
  exit 1
fi
rm -rf /tmp/bpftune

# --- Post-install smoke checks ---
echo "=== Running post-install smoke checks ==="
errors=0

check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK: $cmd"
  else
    echo "  FAIL: $cmd not found" >&2
    errors=$((errors + 1))
  fi
}

check_file() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  OK: $path"
  else
    echo "  FAIL: $path not found" >&2
    errors=$((errors + 1))
  fi
}

# Critical binaries
check_command kitty
check_command code
check_command zed
check_command scx_lavd
check_command opencode
check_command bpftune

# Critical files
check_file /usr/lib64/ladspa/librnnoise_ladspa.so
check_file /etc/systemd/system/multi-user.target.wants/bpftune.service

# Optional binaries (may not be present on all base images)
for cmd in pcmanfm-qt lact lmstudio vicinae; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK (optional): $cmd"
  else
    echo "  SKIP (optional): $cmd"
  fi
done

# Heroic command names vary by package
if command -v heroic >/dev/null 2>&1 || command -v heroic-games-launcher >/dev/null 2>&1; then
  echo "  OK: heroic launcher"
else
  echo "  FAIL: heroic launcher not found" >&2
  errors=$((errors + 1))
fi

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} smoke check(s) failed" >&2
  exit 1
fi

# Cleanup
"${DNF[@]}" clean all || true
# Note: /var/cache/libdnf5 is a BuildKit cache mount and cannot be removed.

echo "=== Latest applications installed successfully ==="
