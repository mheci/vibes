#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing Latest Applications ==="

install_latest_rpm() {
  local repo="$1" pattern="$2" name="$3"
  local url rpm
  if rpm -q "$name" >/dev/null 2>&1; then
    echo "INFO: RPM $name already installed, attempting upgrade" >&2
  fi
  url="$(gh_latest_asset_url "$repo" "$pattern")"
  rpm="/tmp/${name}.rpm"
  echo "Installing latest ${name} RPM from ${url}"
  retry curl -fL --retry 4 --retry-delay 10 -o "$rpm" "$url"
  retry "${DNF[@]}" install --skip-unavailable --skip-broken "$rpm" || echo "WARN: RPM $rpm install skipped (may already be installed)" >&2
  rm -f "$rpm"
}

install_latest_appimage() {
  local repo="$1" pattern="$2" binary="$3" desktop_name="$4"
  local comment="$5" categories="${6:-Utility;}"
  local url path icon_dir
  url="$(gh_latest_asset_url "$repo" "$pattern")"
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

echo "Installing Zen Browser..."
install -d -m 0755 /usr/lib/zen-browser /usr/share/applications
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/zen-linux-x86_64.tar.xz \
  'https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz'
rm -rf /tmp/zen-extract
mkdir -p /tmp/zen-extract
tar -xJf /tmp/zen-linux-x86_64.tar.xz -C /tmp/zen-extract
rm -rf /usr/lib/zen-browser/*
cp -a /tmp/zen-extract/zen/. /usr/lib/zen-browser/
ln -sf /usr/lib/zen-browser/zen /usr/bin/zen-browser
ln -sf /usr/lib/zen-browser/zen /usr/bin/zen
cat >/usr/share/applications/zen-browser.desktop <<'ZENDESKTOP'
[Desktop Entry]
Name=Zen Browser
Comment=Firefox fork focused on privacy and customisation
Exec=/usr/bin/zen-browser %U
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;
StartupNotify=true
ZENDESKTOP
if [[ -d /usr/lib/zen-browser/browser/chrome/icons/default ]]; then
  install -d -m 0755 /usr/share/icons/hicolor/256x256/apps
  cp /usr/lib/zen-browser/browser/chrome/icons/default/default256.png \
    /usr/share/icons/hicolor/256x256/apps/zen-browser.png 2>/dev/null || true
fi
install -d -m 0755 /usr/lib/zen-browser/distribution
cat >/usr/lib/zen-browser/distribution/policies.json <<'JSON'
{
  "policies": {
    "Preferences": {
      "media.ffmpeg.vaapi.enabled": { "Value": true, "Status": "default" },
      "media.hardware-video-decoding.force-enabled": { "Value": true, "Status": "default" },
      "gfx.webrender.all": { "Value": true, "Status": "default" }
    }
  }
}
JSON
rm -rf /tmp/zen-extract /tmp/zen-linux-x86_64.tar.xz

install_latest_rpm "anomalyco/opencode" 'opencode-desktop-linux-x86_64\.rpm$' "opencode-desktop"

install_latest_rpm "Foundry376/Mailspring" 'mailspring-.*\.x86_64\.rpm$' "mailspring"

install_latest_rpm "ferdium/ferdium-app" 'Ferdium-linux-.*-x86_64\.rpm$' "ferdium"

# Sniffnet: network monitoring and analysis tool (official release RPM)
install_latest_rpm "GyulyVGC/sniffnet" 'Sniffnet_LinuxRPM_x86_64\.rpm$' "sniffnet"

echo "Installing proton-cachyos..."
compat_dir="/usr/share/steam/compatibilitytools.d/proton-cachyos"
install -d -m 0755 /tmp/proton-cachyos "${compat_dir%/proton-cachyos}"
proton_url="$(gh_latest_asset_url "CachyOS/proton-cachyos" 'proton-cachyos-.*-x86_64_v3\.tar\.xz$')"
proton_sum_url="${proton_url%.tar.xz}.sha512sum"
echo "Downloading proton-cachyos from ${proton_url}"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/proton-cachyos.tar.xz "$proton_url"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/proton-cachyos.sha512sum "$proton_sum_url"
expected="$(awk '/proton-cachyos/{print $1; exit}' /tmp/proton-cachyos.sha512sum)"
actual="$(sha512sum /tmp/proton-cachyos.tar.xz | awk '{print $1}')"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "ERROR: proton-cachyos sha512 verification failed" >&2
  exit 1
fi
echo "proton-cachyos sha512 verified"
rm -rf "${compat_dir}" /tmp/proton-cachyos/*
tar -xJf /tmp/proton-cachyos.tar.xz -C /tmp/proton-cachyos --strip-components=1
cp -a /tmp/proton-cachyos/. "${compat_dir}/"
if [[ ! -x "${compat_dir}/proton" ]]; then
  echo "ERROR: proton-cachyos extraction missing 'proton' entry point" >&2
  exit 1
fi
rm -rf /tmp/proton-cachyos /tmp/proton-cachyos.tar.xz /tmp/proton-cachyos.sha512sum

echo "Installing LM Studio..."
install -d -m 0755 /usr/lib/vibes-apps/lmstudio /usr/share/applications /usr/bin
retry curl -fL --retry 4 --retry-delay 10 \
  -o /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage \
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

install_latest_appimage "vicinaehq/vicinae" \
  'Vicinae-x86_64\.AppImage$' "vicinae" "Vicinae" \
  "Raycast-inspired launcher" "Utility;"

install_latest_appimage "pingdotgg/t3code" \
  'T3-Code-[0-9.]+-x86_64\.AppImage$' "t3code" "T3 Code" \
  "Opinionated code editor built on Electron" "Development;"

install_latest_appimage "pkgforge-dev/Gear-Lever-AppImage" \
  'Gear_Lever-.*-anylinux-x86_64\.AppImage$' "gear-lever" "Gear Lever" \
  "AppImage manager and launcher" "Utility;"

echo "Installing MangoJuice..."
MJ_ZIP_URL="$(gh_latest_asset_url "radiolamp/mangojuice" \
  'MangoJuice-AppImagename-x86_64\.zip$')"
rm -rf /tmp/mangojuice /tmp/mangojuice.zip
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/mangojuice.zip "${MJ_ZIP_URL}"
mkdir -p /tmp/mangojuice
unzip -q /tmp/mangojuice.zip -d /tmp/mangojuice
mj_app="$(find /tmp/mangojuice -type f -name '*.AppImage' | head -n1)"
if [[ -z "${mj_app}" ]]; then
  echo "ERROR: MangoJuice AppImage not found in release zip" >&2
  exit 1
fi
install -d -m 0755 /usr/lib/vibes-apps/mangojuice /usr/share/applications
install -Dm755 "${mj_app}" /usr/lib/vibes-apps/mangojuice/MangoJuice.AppImage
cat >/usr/bin/mangojuice <<'EOFMJ'
#!/usr/bin/env bash
exec /usr/lib/vibes-apps/mangojuice/MangoJuice.AppImage "$@"
EOFMJ
chmod 0755 /usr/bin/mangojuice
cat >/usr/share/applications/mangojuice.desktop <<'EOFMJDESKTOP'
[Desktop Entry]
Name=MangoJuice
Comment=MangoHud configuration GUI
Exec=/usr/bin/mangojuice %U
Terminal=false
Type=Application
Categories=Game;Settings;
StartupNotify=true
EOFMJDESKTOP
rm -rf /tmp/mangojuice /tmp/mangojuice.zip

echo "Installing Mission Center..."
MC_PROJECT="mission-center-devs%2Fmission-center"
MC_API="https://gitlab.com/api/v4/projects/${MC_PROJECT}/releases/permalink/latest"
MC_URL="$(retry curl -fsSL --max-time 30 "${MC_API}" \
  | jq -r --arg p 'AppImage.*x86_64' \
    '[(.assets.links // [])[] | select(.name | test($p))][0].direct_asset_url // empty')"
if [[ -z "${MC_URL}" ]]; then
  echo "ERROR: Mission Center x86_64 AppImage link not found in GitLab latest release" >&2
  exit 1
fi
install -d -m 0755 /usr/lib/vibes-apps/mission-center /usr/share/applications
retry curl -fL --retry 4 --retry-delay 10 \
  -o /usr/lib/vibes-apps/mission-center/MissionCenter.AppImage "${MC_URL}"
chmod 0755 /usr/lib/vibes-apps/mission-center/MissionCenter.AppImage
cat >/usr/bin/mission-center <<'EOFMC'
#!/usr/bin/env bash
exec /usr/lib/vibes-apps/mission-center/MissionCenter.AppImage "$@"
EOFMC
chmod 0755 /usr/bin/mission-center
cat >/usr/share/applications/mission-center.desktop <<'EOFMCDESKTOP'
[Desktop Entry]
Name=Mission Center
Comment=System/GPU monitoring and control center
Exec=/usr/bin/mission-center %U
Terminal=false
Type=Application
Categories=System;Monitor;
StartupNotify=true
EOFMCDESKTOP

echo "Installing opencode CLI..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/opencode-cli.tar.gz \
  "$(gh_latest_asset_url "anomalyco/opencode" 'opencode-linux-x64\.tar\.gz$')"
rm -rf /tmp/opencode-cli
mkdir -p /tmp/opencode-cli
tar -xzf /tmp/opencode-cli.tar.gz -C /tmp/opencode-cli
cli_bin="$(find /tmp/opencode-cli -type f -name opencode | head -n1)"
if [[ -z "${cli_bin}" ]]; then
  echo "ERROR: opencode binary not found in release tarball" >&2
  exit 1
fi
install -Dm755 "${cli_bin}" /usr/bin/opencode
rm -rf /tmp/opencode-cli /tmp/opencode-cli.tar.gz

echo "Installing RNNoise LADSPA plugin..."
RNNOISE_TAG="v1.10"
install -d -m 0755 /usr/lib64/rnnoise /usr/lib64/ladspa
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/linux-rnnoise.zip \
  "https://github.com/werman/noise-suppression-for-voice/releases/download/${RNNOISE_TAG}/linux-rnnoise.zip"
rm -rf /tmp/linux-rnnoise
unzip -q /tmp/linux-rnnoise.zip -d /tmp/linux-rnnoise
ladspa_so="$(find /tmp/linux-rnnoise -type f -name 'librnnoise_ladspa.so' | head -n1)"
if [[ -z "${ladspa_so}" ]]; then
  echo "ERROR: librnnoise_ladspa.so not found in RNNoise release ${RNNOISE_TAG}" >&2
  exit 1
fi
install -Dm755 "${ladspa_so}" /usr/lib64/ladspa/librnnoise_ladspa.so
if [[ -d /tmp/linux-rnnoise ]]; then
  cp -a /tmp/linux-rnnoise/. /usr/lib64/rnnoise/ 2>/dev/null || true
fi
rm -rf /tmp/linux-rnnoise /tmp/linux-rnnoise.zip

echo "Building and installing bpftune from upstream..."
install_available kernel-headers

BPFTUNE_PIN="4712347f2da0b7d4a5fbdb0d81d071c1704b3f20"
rm -rf /tmp/bpftune
install -d -m 0755 /tmp/bpftune
git -C /tmp/bpftune init -q
git -C /tmp/bpftune remote add origin https://github.com/oracle/bpftune.git
retry git -C /tmp/bpftune fetch -q --depth 1 origin "${BPFTUNE_PIN}"
git -C /tmp/bpftune checkout -q FETCH_HEAD
sed -i 's/^[[:space:]]*bpftune_server_port;/		bpftuner_server_port;/' /tmp/bpftune/src/libbpftune.map
make -C /tmp/bpftune -j"$(nproc)"
make -C /tmp/bpftune install
ldconfig || true

install -d -m 0755 /etc/systemd/system/multi-user.target.wants
bpftune_service=""
for candidate in /usr/lib/systemd/system/bpftune.service /lib/systemd/system/bpftune.service; do
  if [[ -f "$candidate" ]]; then
    bpftune_service="$candidate"
    break
  fi
done
if [[ -n "$bpftune_service" ]]; then
  ln -sf "${bpftune_service}" /etc/systemd/system/multi-user.target.wants/bpftune.service
else
  echo "ERROR: bpftune.service unit file not found after install" >&2
  exit 1
fi
rm -rf /tmp/bpftune

echo "Building and installing nohang from upstream..."
NOHANG_PIN="5938a2e2249cb93ff21094dd548f770c47cc1860"
rm -rf /tmp/nohang
install -d -m 0755 /tmp/nohang
git -C /tmp/nohang init -q
git -C /tmp/nohang remote add origin https://github.com/hakavlad/nohang.git
retry git -C /tmp/nohang fetch -q --depth 1 origin "${NOHANG_PIN}"
git -C /tmp/nohang checkout -q FETCH_HEAD
make -C /tmp/nohang install PREFIX=/usr SYSCONFDIR=/etc \
  SYSTEMDUNITDIR=/usr/lib/systemd/system
if [[ -f /usr/lib/systemd/system/nohang-desktop.service ]]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/nohang-desktop.service \
    /etc/systemd/system/multi-user.target.wants/nohang-desktop.service
else
  echo "ERROR: nohang-desktop.service unit file not found after install" >&2
  exit 1
fi
rm -rf /tmp/nohang

echo "Building and installing prelockd from upstream..."
PRELOCKD_PIN="584f70ac05b403237a12193f1e70380b283d4083"
rm -rf /tmp/prelockd
install -d -m 0755 /tmp/prelockd
git -C /tmp/prelockd init -q
git -C /tmp/prelockd remote add origin https://github.com/hakavlad/prelockd.git
retry git -C /tmp/prelockd fetch -q --depth 1 origin "${PRELOCKD_PIN}"
git -C /tmp/prelockd checkout -q FETCH_HEAD
make -C /tmp/prelockd install PREFIX=/usr SYSCONFDIR=/etc \
  SYSTEMDUNITDIR=/usr/lib/systemd/system
if [[ -f /usr/lib/systemd/system/prelockd.service ]]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/prelockd.service \
    /etc/systemd/system/multi-user.target.wants/prelockd.service
else
  echo "ERROR: prelockd.service unit file not found after install" >&2
  exit 1
fi
rm -rf /tmp/prelockd


echo "Installing qui (qBittorrent web UI)..."
QUI_VERSION="v1.23.0"
QUI_URL="https://github.com/autobrr/qui/releases/download/${QUI_VERSION}/qui_${QUI_VERSION#v}_linux_x86_64.tar.gz"
install -d -m 0755 /usr/local/bin
# No -f here: a missing pinned asset must fall through to the latest
# release fallback below instead of hard-failing the build.
retry curl -L --retry 4 --retry-delay 10 -o /tmp/qui.tar.gz "${QUI_URL}"
if ! tar -C /usr/local/bin -xzf /tmp/qui.tar.gz 2>/dev/null || [[ ! -x /usr/local/bin/qui ]]; then
  echo "WARN: qui ${QUI_VERSION} download failed, trying latest release..." >&2
  rm -f /tmp/qui.tar.gz
  QUI_URL="$(gh_latest_asset_url "autobrr/qui" 'linux_x86_64\.tar\.gz$')"
  if [[ -n "${QUI_URL}" ]]; then
    retry curl -fL --retry 4 --retry-delay 10 -o /tmp/qui.tar.gz "${QUI_URL}"
    tar -C /usr/local/bin -xzf /tmp/qui.tar.gz 2>/dev/null || true
  fi
fi
chmod 0755 /usr/local/bin/qui 2>/dev/null || true
rm -f /tmp/qui.tar.gz

echo "Installing Nix (Determinate Systems installer, ${NIX_INSTALLER_TAG})..."

NIX_INSTALLER_TAG="v3.21.9"
NIX_INSTALL_LOG="/tmp/nix-install.log"
if [[ ! -x /var/nix/var/nix/profiles/default/bin/nix ]]; then
  # The nix-installer release page publishes no checksums, so the
  # pinned-tag release binary is fetched from the GitHub release API
  # and its version is verified against the pinned tag before running.
  NIX_BIN_URL="$(gh_asset_url "DeterminateSystems/nix-installer" 'nix-installer-x86_64-linux$' "${NIX_INSTALLER_TAG}")"
  retry curl -fL --retry 4 --retry-delay 10 -o /tmp/nix-installer "${NIX_BIN_URL}"
  chmod 0755 /tmp/nix-installer
  if ! /tmp/nix-installer --version 2>/dev/null | grep -q "nix-installer ${NIX_INSTALLER_TAG#v}"; then
    echo "ERROR: nix-installer version verification failed" >&2
    /tmp/nix-installer --version 2>/dev/null || true
    exit 1
  fi
  if /tmp/nix-installer install linux --init none --no-confirm \
      >"${NIX_INSTALL_LOG}" 2>&1; then
    echo "Nix installed successfully"
  else
    echo "ERROR: Nix installation failed" >&2
    tail -n 50 "${NIX_INSTALL_LOG}" >&2
    exit 1
  fi
fi
rm -f "${NIX_INSTALL_LOG}" /tmp/nix-installer

if [[ -d /nix/var && ! -d /var/nix/var ]]; then
  echo "Moving Nix store to /var/nix (persistent ostree state)..."
  rm -rf /var/nix
  mv /nix /var/nix
  install -d -m 0755 /nix
fi

NIX_POLICY_SRC="https://raw.githubusercontent.com/DeterminateSystems/nix-installer/${NIX_INSTALLER_TAG}/src/action/linux/selinux/determinate-nix.pp"
if [[ ! -f /usr/share/selinux/packages/determinate-nix.pp ]]; then
  install -d -m 0755 /usr/share/selinux/packages
  retry curl -fL --retry 4 --retry-delay 10 \
    -o /usr/share/selinux/packages/determinate-nix.pp "${NIX_POLICY_SRC}"
fi

cat >/usr/lib/systemd/system/nix.mount <<'NIXMOUNT'
[Unit]
Description=Nix Package Manager
After=systemd-remount-fs.service

[Mount]
What=/var/nix
Where=/nix
Options=bind
Type=none

[Install]
WantedBy=multi-user.target
NIXMOUNT

cat >/usr/lib/systemd/system/nix-daemon.service <<'NIXUNIT'
[Unit]
Description=Nix Daemon
Documentation=man:nix-daemon https://nixos.org/manual
RequiresMountsFor=/nix/store
RequiresMountsFor=/nix/var
RequiresMountsFor=/nix/var/nix/db
ConditionPathIsReadWrite=/nix/var/nix/daemon-socket
After=nix.mount vibes-nix-selinux.service
Requires=nix.mount

[Service]
ExecStart=/nix/var/nix/profiles/default/bin/nix-daemon nix-daemon --daemon
KillMode=process
LimitNOFILE=1048576
TasksMax=1048576
Delegate=

[Install]
WantedBy=multi-user.target
NIXUNIT

cat >/usr/lib/systemd/system/nix-daemon.socket <<'NIXSOCKET'
[Unit]
Description=Nix Daemon Socket
Before=multi-user.target
RequiresMountsFor=/nix/store
ConditionPathIsReadWrite=/nix/var/nix/daemon-socket
After=nix.mount vibes-nix-selinux.service
Requires=nix.mount

[Socket]
ListenStream=/nix/var/nix/daemon-socket/socket

[Install]
WantedBy=sockets.target
NIXSOCKET

cat >/usr/lib/systemd/system/vibes-nix-selinux.service <<'NIXSELINUX'
[Unit]
Description=Install Nix SELinux policy module
ConditionSecurity=selinux
After=nix.mount
Before=nix-daemon.service nix-daemon.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/semodule --install /usr/share/selinux/packages/determinate-nix.pp
ExecStart=/usr/sbin/restorecon -FR /nix

[Install]
WantedBy=multi-user.target
NIXSELINUX

install -d -m 0755 /etc/systemd/system/multi-user.target.wants \
  /etc/systemd/system/sockets.target.wants
for unit in nix.mount nix-daemon.service vibes-nix-selinux.service; do
  ln -sf "/usr/lib/systemd/system/${unit}" \
    "/etc/systemd/system/multi-user.target.wants/${unit}"
done
ln -sf /usr/lib/systemd/system/nix-daemon.socket \
  /etc/systemd/system/sockets.target.wants/nix-daemon.socket

cat >/etc/profile.d/nix.sh <<'NIXPROFILE'
if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
NIXPROFILE

echo "Installing bun..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/bun.zip \
  "$(gh_latest_asset_url "oven-sh/bun" 'bun-linux-x64\.zip$')"
rm -rf /tmp/bun-x
mkdir -p /tmp/bun-x
unzip -q /tmp/bun.zip -d /tmp/bun-x
bun_bin="$(find /tmp/bun-x -type f -name bun -perm -111 | head -n1)"
if [[ -z "${bun_bin}" ]]; then
  echo "ERROR: bun binary not found in release zip" >&2
  exit 1
fi
install -Dm755 "${bun_bin}" /usr/local/bin/bun
ln -sf /usr/local/bin/bun /usr/local/bin/bunx
rm -rf /tmp/bun-x /tmp/bun.zip

echo "Installing deno..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/deno.zip \
  "$(gh_latest_asset_url "denoland/deno" 'deno-x86_64-unknown-linux-gnu\.zip$')"
rm -rf /tmp/deno-x
mkdir -p /tmp/deno-x
unzip -q /tmp/deno.zip -d /tmp/deno-x
deno_bin="$(find /tmp/deno-x -type f -name deno | head -n1)"
if [[ -z "${deno_bin}" ]]; then
  echo "ERROR: deno binary not found in release zip" >&2
  exit 1
fi
install -Dm755 "${deno_bin}" /usr/local/bin/deno
rm -rf /tmp/deno-x /tmp/deno.zip

echo "Installing zellij..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/zellij.tar.gz \
  "$(gh_latest_asset_url "zellij-org/zellij" 'zellij-x86_64-unknown-linux-musl\.tar\.gz$')"
rm -rf /tmp/zellij-x
mkdir -p /tmp/zellij-x
tar -xzf /tmp/zellij.tar.gz -C /tmp/zellij-x
zellij_bin="$(find /tmp/zellij-x -type f -name zellij -perm -111 | head -n1)"
if [[ -z "${zellij_bin}" ]]; then
  echo "ERROR: zellij binary not found in release tarball" >&2
  exit 1
fi
install -Dm755 "${zellij_bin}" /usr/local/bin/zellij
rm -rf /tmp/zellij-x /tmp/zellij.tar.gz

echo "Installing glance..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/glance.tar.gz \
  "$(gh_latest_asset_url "glanceapp/glance" 'glance-linux-amd64\.tar\.gz$')"
rm -rf /tmp/glance-x
mkdir -p /tmp/glance-x
tar -xzf /tmp/glance.tar.gz -C /tmp/glance-x
glance_bin="$(find /tmp/glance-x -type f -name glance -perm -111 | head -n1)"
if [[ -z "${glance_bin}" ]]; then
  echo "ERROR: glance binary not found in release tarball" >&2
  exit 1
fi
install -Dm755 "${glance_bin}" /usr/local/bin/glance
rm -rf /tmp/glance-x /tmp/glance.tar.gz

echo "Installing bottom..."
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/bottom.tar.gz \
  "$(gh_latest_asset_url "ClementTsang/bottom" 'bottom_x86_64-unknown-linux-gnu\.tar\.gz$')"
rm -rf /tmp/bottom-x
mkdir -p /tmp/bottom-x
tar -xzf /tmp/bottom.tar.gz -C /tmp/bottom-x
btm_bin="$(find /tmp/bottom-x -type f -name btm -perm -111 | head -n1)"
if [[ -z "${btm_bin}" ]]; then
  echo "ERROR: btm binary not found in release tarball" >&2
  exit 1
fi
install -Dm755 "${btm_bin}" /usr/local/bin/btm
rm -rf /tmp/bottom-x /tmp/bottom.tar.gz

echo "Installing Commet..."
COMMET_URL="$(gh_latest_asset_url "commetchat/commet" \
  'commet-linux-portable-x64\.tar\.gz$')"
rm -rf /tmp/commet /tmp/commet-extract
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/commet.tar.gz "${COMMET_URL}"
mkdir -p /tmp/commet-extract
tar -xzf /tmp/commet.tar.gz -C /tmp/commet-extract --strip-components=1
commet_bin="$(find /tmp/commet-extract -type f -name commet -perm -111 | head -n1)"
if [[ -z "${commet_bin}" ]]; then
  echo "ERROR: commet binary not found in tarball" >&2
  exit 1
fi
install -d -m 0755 /usr/lib/commet
cp -a /tmp/commet-extract/. /usr/lib/commet/
ln -sf /usr/lib/commet/commet /usr/bin/commet
cat >/usr/share/applications/commet.desktop <<'COMMETDESKTOP'
[Desktop Entry]
Name=Commet
Comment=Chat with Matrix
Exec=/usr/bin/commet %U
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/commet;
StartupNotify=true
COMMETDESKTOP
commet_icon="$(find /usr/lib/commet -type f -name 'app_icon_rounded.png' | head -n1)"
if [[ -n "${commet_icon}" ]]; then
  install -d -m 0755 /usr/share/icons/hicolor/512x512/apps
  install -m 0644 "${commet_icon}" /usr/share/icons/hicolor/512x512/apps/commet.png
fi
rm -rf /tmp/commet /tmp/commet-extract /tmp/commet.tar.gz

echo "Installing CachyOS ananicy rules..."
ANANICY_TAG="1.1.47"
rm -rf /tmp/ananicy-rules
install -d -m 0755 /tmp/ananicy-rules
git -C /tmp/ananicy-rules init -q
git -C /tmp/ananicy-rules remote add origin \
  https://github.com/CachyOS/ananicy-rules.git
retry git -C /tmp/ananicy-rules fetch -q --depth 1 origin "refs/tags/${ANANICY_TAG}"
git -C /tmp/ananicy-rules checkout -q FETCH_HEAD
install -d -m 0755 /etc/ananicy.d
cp -a /tmp/ananicy-rules/00-default /etc/ananicy.d/
cp -a /tmp/ananicy-rules/00-cgroups.cgroups /tmp/ananicy-rules/00-types.types \
  /tmp/ananicy-rules/ananicy.conf /etc/ananicy.d/
rm -rf /tmp/ananicy-rules

install_github_fonts() {
  local repo="$1" pattern="$2" family="$3"
  local url zip
  echo "Installing ${family} fonts..."
  url="$(gh_latest_asset_url "$repo" "$pattern")"
  zip="/tmp/${family}-fonts.zip"
  retry curl -fL --retry 4 --retry-delay 10 -o "$zip" "$url"
  rm -rf "/tmp/${family}-fonts"
  mkdir -p "/tmp/${family}-fonts"
  unzip -q "$zip" -d "/tmp/${family}-fonts"
  install -d -m 0755 "/usr/share/fonts/${family}"
  find "/tmp/${family}-fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) \
    -exec install -m 0644 {} "/usr/share/fonts/${family}/" \;
  rm -rf "/tmp/${family}-fonts" "$zip"
}

install_github_fonts "githubnext/monaspace" 'monaspace-static-v[0-9.]+\.zip$' "monaspace"

install_github_fonts "rsms/inter" 'Inter-[0-9.]+\.zip$' "inter"

install_github_fonts "mishamyrt/Lilex" 'Lilex\.zip$' "lilex"

install_github_fonts "SpaceTimee/Fusion-JetBrainsMapleMono" \
  'JetBrainsMapleMono-XX-XX-XX-XX\.zip$' "fusion-jetbrainsmaplemono"

fc-cache -f >/dev/null 2>&1 || true

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

check_command kitty
check_command code
check_command zed
check_command zen-browser
check_command scx_lavd
check_command opencode
check_command bpftune
check_command yazi
check_command mpv
check_command mailspring
check_command ferdium
check_command brave-origin
check_command steam
check_command gamescope
check_command mangohud
check_command nicotine

if [[ -x /usr/share/steam/compatibilitytools.d/proton-cachyos/proton ]]; then
  echo "  OK: proton-cachyos (compatibility tool)"
else
  echo "  FAIL: proton-cachyos not installed" >&2
  errors=$((errors + 1))
fi

for unit in uresourced low-memory-monitor nohang-desktop prelockd; do
  check_file "/etc/systemd/system/multi-user.target.wants/${unit}.service"
done
for pkg in uresourced low-memory-monitor; do
  if rpm -q "$pkg" >/dev/null 2>&1; then
    echo "  OK: $pkg (rpm)"
  else
    echo "  FAIL: $pkg not installed" >&2
    errors=$((errors + 1))
  fi
done
check_command nohang
check_command prelockd
check_file /etc/low-memory-monitor.conf
if [[ -e /usr/lib/systemd/system/systemd-oomd.service ]]; then
  check_file /etc/systemd/system/systemd-oomd.service
fi

for pkg in tuned tuned-ppd; do
  if rpm -q "$pkg" >/dev/null 2>&1; then
    echo "  OK: $pkg (rpm)"
  else
    echo "  FAIL: $pkg not installed" >&2
    errors=$((errors + 1))
  fi
done
for unit in tuned.service tuned-ppd.service; do
  check_file "/etc/systemd/system/multi-user.target.wants/${unit}"
done
check_file /etc/tuned/ppd.conf
if grep -q 'performance=latency-performance' /etc/tuned/ppd.conf 2>/dev/null; then
  echo "  OK: tuned PPD mapping performance->latency-performance"
else
  echo "  FAIL: tuned PPD performance mapping missing" >&2
  errors=$((errors + 1))
fi

check_file /etc/environment.d/90-vibes-desktop-env.conf
if grep -q '^VKD3D_CONFIG=descriptor_heap$' /etc/environment.d/90-vibes-desktop-env.conf 2>/dev/null; then
  echo "  OK: VKD3D_CONFIG=descriptor_heap"
else
  echo "  FAIL: VKD3D_CONFIG missing" >&2
  errors=$((errors + 1))
fi
if grep -q '^QT_LOGGING_RULES=.*\.debug=false.*\.info=false' /etc/environment.d/90-vibes-desktop-env.conf 2>/dev/null; then
  echo "  OK: Qt logging silenced (warnings+)"
else
  echo "  FAIL: QT_LOGGING_RULES missing" >&2
  errors=$((errors + 1))
fi
for var in '__GL_SHADER_DISK_CACHE_PATH' 'MESA_SHADER_CACHE_DIR' 'DXVK_STATE_CACHE_PATH'; do
  if grep -qF "${var}=" /etc/environment.d/90-vibes-desktop-env.conf 2>/dev/null; then
    echo "  OK: ${var} pinned to persistent cache"
  else
    echo "  FAIL: ${var} missing" >&2
    errors=$((errors + 1))
  fi
done

for policy in /etc/opt/chrome/policies/managed/vibes-hw-accel.json \
    /etc/chromium/policies/managed/vibes-hw-accel.json \
    /etc/brave/policies/managed/vibes-hw-accel.json; do
  check_file "$policy"
done
check_file /etc/chromium-flags.conf
check_file /etc/mpv/mpv.conf
if grep -q '^hwdec=auto-safe$' /etc/mpv/mpv.conf 2>/dev/null; then
  echo "  OK: mpv hardware decode enabled"
else
  echo "  FAIL: mpv hwdec config missing" >&2
  errors=$((errors + 1))
fi
if [[ -d /usr/lib/zen-browser ]]; then
  check_file /usr/lib/zen-browser/distribution/policies.json
fi

check_file /etc/systemd/system/vibes-selinux.service
check_file /etc/systemd/system/multi-user.target.wants/vibes-selinux.service

for cmd in uv hx yt-dlp gh zoxide bun deno t3code; do
  check_command "$cmd"
done

for cmd in eza bat fd rg fzf duf btm; do
  check_command "$cmd"
done

for cmd in sensors nvtop gparted fastfetch; do
  check_command "$cmd"
done
if rpm -q dolphin-plugins >/dev/null 2>&1; then
  echo "  OK: dolphin-plugins (rpm)"
else
  echo "  FAIL: dolphin-plugins not installed" >&2
  errors=$((errors + 1))
fi

for cmd in tmux zellij lollypop rhythmbox fragments trivy \
    commet qbittorrent glance sniffnet; do
  check_command "$cmd"
done

for cmd in nautilus gnome-disks dolphin; do
  check_command "$cmd"
done
gvfs_backends=0
gvfs_missing=()
for gvfs_pkg in gvfs gvfs-mtp gvfs-smb gvfs-afp gvfs-archive gvfs-fuse \
    gvfs-nfs gvfs-goa gvfs-gphoto2; do
  if rpm -q "${gvfs_pkg}" >/dev/null 2>&1; then
    gvfs_backends=$((gvfs_backends + 1))
  else
    gvfs_missing+=("${gvfs_pkg}")
  fi
done
if [[ ${gvfs_backends} -ge 5 ]]; then
  echo "  OK: ${gvfs_backends} GVFS backends installed"
else
  echo "  FAIL: only ${gvfs_backends} GVFS backends installed (${gvfs_missing[*]})" >&2
  errors=$((errors + 1))
fi

check_file /etc/ananicy.d/ananicy.conf
check_file /etc/ananicy.d/00-types.types
if [[ -d /etc/ananicy.d/00-default ]]; then
  echo "  OK: /etc/ananicy.d/00-default rules"
else
  echo "  FAIL: /etc/ananicy.d/00-default rules not found" >&2
  errors=$((errors + 1))
fi

if rpm -q sudo-rs >/dev/null 2>&1; then
  echo "  OK: sudo-rs (rpm)"
else
  echo "  FAIL: sudo-rs not installed" >&2
  errors=$((errors + 1))
fi

if [[ -d /var/nix/store ]] && [[ -n "$(find /var/nix/store -maxdepth 5 \( -type f -o -type l \) -name nix 2>/dev/null | head -n1)" ]]; then
  echo "  OK: nix store (binary present)"
else
  echo "  FAIL: nix store not populated" >&2
  errors=$((errors + 1))
fi
if [[ -L /var/nix/var/nix/profiles/default || -e /var/nix/var/nix/profiles/default ]]; then
  echo "  OK: nix default profile link"
else
  echo "  FAIL: nix default profile link not found" >&2
  errors=$((errors + 1))
fi
for unit in nix.mount nix-daemon.service nix-daemon.socket \
    vibes-nix-selinux.service; do
  check_file "/usr/lib/systemd/system/${unit}"
done
check_file /etc/systemd/system/multi-user.target.wants/nix.mount
check_file /etc/systemd/system/multi-user.target.wants/nix-daemon.service
check_file /etc/systemd/system/sockets.target.wants/nix-daemon.socket
check_file /usr/share/selinux/packages/determinate-nix.pp
check_file /etc/profile.d/nix.sh
check_file /etc/sudoers.d/99-vibes-wheel-nopasswd

for dir in monaspace inter lilex fusion-jetbrainsmaplemono \
    source-code-pro; do
  if find /usr/share/fonts -maxdepth 2 -type d -iname "*${dir}*" \
      | grep -q .; then
    echo "  OK: font ${dir}"
  else
    echo "  FAIL: font ${dir} not installed" >&2
    errors=$((errors + 1))
  fi
done

if rpm -q faugus-launcher >/dev/null 2>&1; then
  echo "  OK: faugus-launcher (rpm)"
else
  echo "  FAIL: faugus-launcher not installed" >&2
  errors=$((errors + 1))
fi

check_file /usr/lib64/ladspa/librnnoise_ladspa.so
check_file /etc/systemd/system/multi-user.target.wants/bpftune.service
check_file /usr/share/icons/MoreWaita/index.theme
check_file /usr/share/themes/Yaru/index.theme
check_file /usr/share/icons/Yaru/index.theme
if rpm -q kdeconnectd >/dev/null 2>&1; then
  echo "  OK: kdeconnectd (rpm)"
else
  echo "  FAIL: kdeconnectd not installed" >&2
  errors=$((errors + 1))
fi

for cmd in lact lmstudio vicinae ananicy-cpp qui helium zen \
    mission-center gear-lever mangojuice; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK (optional): $cmd"
  else
    echo "  SKIP (optional): $cmd"
  fi
done

# Files-module configuration and service binaries.
for f in /etc/containers/policy.json \
    /etc/pki/containers/vibes-cosign.pub \
    /etc/xdg/kwinrc /etc/xdg/kdeglobals /etc/xdg/powerdevilrc \
    /etc/fonts/local.conf \
    /usr/share/vibes/justfile \
    /usr/share/vibes/kernel-version \
    /usr/lib/systemd/system/vibes-update-check.service \
    /usr/lib/systemd/system/vibes-update-check.timer \
    /usr/lib/systemd/system/greenboot-task-runner.service; do
  check_file "$f"
done
if [[ -f /etc/systemd/system/multi-user.target.wants/greenboot-health-check.service ]]; then
  echo "  OK: greenboot-health-check.service enabled"
else
  echo "  FAIL: greenboot-health-check.service not enabled" >&2
  errors=$((errors + 1))
fi
for script in /usr/libexec/vibes-update-check.sh \
    /usr/lib/greenboot/check/warning.d/40-systemd-failed.sh \
    /usr/libexec/vibes-luks-tpm-encrypt.sh \
    /usr/libexec/vibes-dns-encrypted.sh; do
  if [[ -x "$script" ]]; then
    echo "  OK: $script (executable)"
  else
    echo "  FAIL: $script missing or not executable" >&2
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} smoke check(s) failed" >&2
  exit 1
fi

echo "--- Cleaning up ---"
clean_build_artifacts

echo "=== Latest applications installed successfully ==="
