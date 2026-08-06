#!/usr/bin/env bash
# Install latest versions of applications from upstream release channels.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing Latest Applications ==="

# ---------------------------------------------------------------------------
# Helper: install latest RPM from a GitHub release
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper: install latest AppImage from a GitHub release
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Zed Editor (latest stable from zed.dev)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Zen Browser (latest stable from GitHub releases, tar.xz)
# ---------------------------------------------------------------------------
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
# Same VA-API/WebRender policy as Firefox, read from the app distribution
# dir at startup (mirrors the Firefox policy from setup-repos-and-rpms.sh).
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

# ---------------------------------------------------------------------------
# GitHub release RPM applications
# ---------------------------------------------------------------------------
install_latest_rpm "anomalyco/opencode" 'opencode-desktop-linux-x86_64\.rpm$' "opencode-desktop"

# Mailspring: cross-platform mail client (Foundry376; official RPM release)
install_latest_rpm "Foundry376/Mailspring" 'mailspring-.*\.x86_64\.rpm$' "mailspring"

# ---------------------------------------------------------------------------
# Ferdium: all-in-one messaging client (WhatsApp, Telegram, Slack, ...).
# Installed from the official upstream RPM published on GitHub Releases
# (latest stable), resolving dependencies through DNF.
# ---------------------------------------------------------------------------
install_latest_rpm "ferdium/ferdium-app" 'Ferdium-linux-.*-x86_64\.rpm$' "ferdium"

# ---------------------------------------------------------------------------
# proton-cachyos (Wayland-first Proton fork, system-wide for Steam)
# Installed from the latest CachyOS/proton-cachyos release: x86_64_v3 build
# (best for this image's x86_64-v3 kernel/userspace), sha512-verified against
# the per-asset checksum file shipped in the same release. Extraction goes to
# /usr/share/steam/compatibilitytools.d so Steam lists it as a compatibility
# tool for every game without per-user setup.
# ---------------------------------------------------------------------------
echo "Installing proton-cachyos..."
compat_dir="/usr/share/steam/compatibilitytools.d/proton-cachyos"
install -d -m 0755 /tmp/proton-cachyos "${compat_dir%/proton-cachyos}"
proton_url="$(gh_latest_asset_url "CachyOS/proton-cachyos" 'proton-cachyos-.*-x86_64_v3\.tar\.xz$')"
proton_sum_url="${proton_url%.tar.xz}.sha512sum"
echo "Downloading proton-cachyos from ${proton_url}"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/proton-cachyos.tar.xz "$proton_url"
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/proton-cachyos.sha512sum "$proton_sum_url"
# Upstream sidecars are "<digest>  <filename>" (or bare digest); take the
# digest column only.
expected="$(awk '{print $1}' /tmp/proton-cachyos.sha512sum)"
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

# ---------------------------------------------------------------------------
# LM Studio (official AppImage)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Vicinae (AppImage; RPM excluded on Bazzite due to mesa-libEGL conflict)
# ---------------------------------------------------------------------------
install_latest_appimage "vicinaehq/vicinae" \
  'Vicinae-x86_64\.AppImage$' "vicinae" "Vicinae" \
  "Raycast-inspired launcher" "Utility;"

# ---------------------------------------------------------------------------
# T3 Code (pingdotgg/t3code; Electron-based editor by Theo - t3.gg)
# No Fedora RPM or Flatpak exists; upstream ships a Linux AppImage.
# ---------------------------------------------------------------------------
install_latest_appimage "pingdotgg/t3code" \
  'T3-Code-[0-9.]+-x86_64\.AppImage$' "t3code" "T3 Code" \
  "Opinionated code editor built on Electron" "Development;"

# ---------------------------------------------------------------------------
# Gear Lever (AppImage manager) - native AppImage conversion
# The original Foldex/gear-lever project is gone; pkgforge-dev maintains an
# up-to-date AppImage (replaces the it.mijorus.gearlever Flatpak).
# ---------------------------------------------------------------------------
install_latest_appimage "pkgforge-dev/Gear-Lever-AppImage" \
  'Gear_Lever-.*-anylinux-x86_64\.AppImage$' "gear-lever" "Gear Lever" \
  "AppImage manager and launcher" "Utility;"

# ---------------------------------------------------------------------------
# MangoJuice (MangoHud configuration GUI) - native AppImage conversion
# Upstream (radiolamp/mangojuice) ships the AppImage inside a zip archive.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Mission Center (system/GPU monitoring) - native AppImage conversion
# Upstream publishes the AppImage as a GitLab release link (job artifact);
# GitLab, not GitHub, so resolve it via the GitLab releases API.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# opencode CLI (pinned to latest GitHub release; the opencode.ai/install
# script fails silently in the OCI build, so download the release tarball)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# RNNoise LADSPA plugin (audio noise suppression)
# Pinned to v1.10; uses pre-built binary from tagged release.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# bpftune (BPF-based auto-tuning daemon)
# Built from source because oracle/bpftune has no release tags.
# ---------------------------------------------------------------------------
echo "Building and installing bpftune from upstream..."
# bpftune compiles its BPF programs against the userspace kernel headers
# (/usr/include, provided by kernel-headers) - kernel-devel is not required.
# The CachyOS kernel's own -devel package covers anything kernel-tree based.
install_available kernel-headers

BPFTUNE_PIN="4712347f2da0b7d4a5fbdb0d81d071c1704b3f20"
rm -rf /tmp/bpftune
install -d -m 0755 /tmp/bpftune
git -C /tmp/bpftune init -q
git -C /tmp/bpftune remote add origin https://github.com/oracle/bpftune.git
retry git -C /tmp/bpftune fetch -q --depth 1 origin "${BPFTUNE_PIN}"
git -C /tmp/bpftune checkout -q FETCH_HEAD
# Upstream bug (since 2024-12-19, commit 2554af924a): src/libbpftune.map lists
# "bpftune_server_port" but libbpftune.c defines "bpftuner_server_port", so the
# shared library link fails with "version script assignment ... symbol not
# defined".  Align the map with the code.
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

# ---------------------------------------------------------------------------
# nohang (sophisticated low-memory handler; replaces systemd-oomd)
# The Fedora package is orphaned (EPEL8 only), so build from upstream like
# the other from-source tools. Pure Python: no build dependencies. The
# desktop variant enables PSI checking and GUI notifications and is the
# upstream-recommended config for desktops.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# prelockd (pin executables/shared libraries in RAM)
# The Fedora package is EPEL8-only; upstream ships a prebuilt binary, so
# this is a pure install - no compiler required.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# NOTE on package policy: this image NEVER installs applications via coding
# language package managers (pip, uv, npm, cargo, go, ...). The package
# managers themselves are installed (from Fedora RPMs / upstream release
# binaries), but end-user tools must ship via Fedora repos, GitLab/GitHub
# RPMs, or direct release artifacts, with Flatpak as the very last resort.
# Software that only exists in a language package manager (npm, uv/pip,
# crates.io, ...) is left out of the image entirely; users can add it at
# runtime with their own tooling if they want it.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# qui (qBittorrent web UI, single binary from GitHub)
# ---------------------------------------------------------------------------
echo "Installing qui (qBittorrent web UI)..."
# Pinned to v1.23.0 (2025-07-13) - update deliberately after testing.
# Fallback to dynamic latest asset via gh_asset_url if pinned fails.
QUI_VERSION="v1.23.0"
QUI_URL="https://github.com/autobrr/qui/releases/download/${QUI_VERSION}/qui_${QUI_VERSION#v}_linux_x86_64.tar.gz"
install -d -m 0755 /usr/local/bin
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/qui.tar.gz "${QUI_URL}"
tar -C /usr/local/bin -xzf /tmp/qui.tar.gz 2>/dev/null || {
  echo "WARN: qui download failed, trying latest release..." >&2
  QUI_URL="$(gh_latest_asset_url "autobrr/qui" 'linux_x86_64\.tar\.gz$')"
  if [[ -n "${QUI_URL}" ]]; then
    retry curl -fL --retry 4 --retry-delay 10 -o /tmp/qui.tar.gz "${QUI_URL}"
    tar -C /usr/local/bin -xzf /tmp/qui.tar.gz 2>/dev/null || true
  fi
}
chmod 0755 /usr/local/bin/qui 2>/dev/null || true
rm -f /tmp/qui.tar.gz

# ---------------------------------------------------------------------------
# Nix (DeterminateSystems/nix-installer, multi-user / rootless for users)
#
# Bluefin is an ostree (bootc) image: the root filesystem is read-only at
# runtime and SELinux is enforcing. The Determinate installer normally uses
# its own ostree planner + SELinux provisioning, but that requires a running
# systemd (present only after first boot, not during image build). Instead:
#
#   1. At build time the installer runs with `--init none` inside the build
#      container (writable /), which skips systemd and SELinux integration.
#   2. The resulting store tree is moved to /var/nix (persistent, writable
#      state on ostree) and an empty /nix mountpoint is kept in the image.
#   3. At runtime, nix.mount bind-mounts /var/nix onto /nix, and systemd
#      socket-activates nix-daemon, giving every user rootless multi-user
#      Nix (the daemon runs as root; clients connect over the unix socket).
#   4. A oneshot service installs the SELinux policy module (nix.pp) and
#      relabels /nix before nix-daemon can start.
# ---------------------------------------------------------------------------
echo "Installing Nix (Determinate Systems installer)..."

NIX_INSTALLER_TAG="v3.21.9"
NIX_INSTALL_LOG="/tmp/nix-install.log"
if [[ ! -x /var/nix/var/nix/profiles/default/bin/nix ]]; then
  if retry curl --proto '=https' --tlsv1.2 -sSf -L \
      "https://install.determinate.systems/nix/tag/${NIX_INSTALLER_TAG}" | \
      sh -s -- install linux --init none --no-confirm \
        >"${NIX_INSTALL_LOG}" 2>&1; then
    echo "Nix installed successfully"
  else
    echo "ERROR: Nix installation failed" >&2
    tail -n 50 "${NIX_INSTALL_LOG}" >&2
    exit 1
  fi
fi
rm -f "${NIX_INSTALL_LOG}"

# Move the store into persistent state (/var) and keep /nix as the runtime
# bind-mountpoint (root is read-only on bootc images).
if [[ -d /nix/var && ! -d /var/nix/var ]]; then
  echo "Moving Nix store to /var/nix (persistent ostree state)..."
  rm -rf /var/nix
  mv /nix /var/nix
  install -d -m 0755 /nix
fi

# SELinux policy module for the Nix daemon (same source the installer
# embeds; the installer skips this in the build container, so we ship it
# and load it at first boot).
NIX_POLICY_SRC="https://raw.githubusercontent.com/DeterminateSystems/nix-installer/${NIX_INSTALLER_TAG}/src/action/linux/selinux/determinate-nix.pp"
if [[ ! -f /usr/share/selinux/packages/determinate-nix.pp ]]; then
  install -d -m 0755 /usr/share/selinux/packages
  retry curl -fL --retry 4 --retry-delay 10 \
    -o /usr/share/selinux/packages/determinate-nix.pp "${NIX_POLICY_SRC}"
fi

# Runtime units: bind mount, daemon service/socket, SELinux policy loader.
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

# Make Nix available in interactive shells (sources the installer's own
# nix-daemon.sh which sets PATH etc. under /nix).
cat >/etc/profile.d/nix.sh <<'NIXPROFILE'
# Source the Determinate Nix shell environment (PATH etc.)
if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
NIXPROFILE

# ---------------------------------------------------------------------------
# bun (JavaScript runtime, single binary from GitHub)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# deno (JavaScript/TypeScript runtime, single binary from GitHub)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# zellij (terminal workspace, single static binary from GitHub)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# glance (self-hosted dashboard, single static binary from GitHub)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Element Desktop (Matrix client). The desktop app source lives in
# element-hq/element-web (apps/desktop); upstream publishes the current
# build as a portable tarball at packages.element.io (the "element-desktop"
# name is a rolling pointer to the newest release, currently 1.12.x).
# Extracted to /usr/lib/element-desktop and wired into the menu.
# ---------------------------------------------------------------------------
echo "Installing Element Desktop..."
ELEMENT_URL="https://packages.element.io/desktop/install/linux/glibc-x86-64/element-desktop.tar.gz"
rm -rf /tmp/element-desktop /tmp/element-extract
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/element-desktop.tar.gz "${ELEMENT_URL}"
mkdir -p /tmp/element-extract
tar -xzf /tmp/element-desktop.tar.gz -C /tmp/element-extract --strip-components=1
element_bin="$(find /tmp/element-extract -type f -name element-desktop -perm -111 | head -n1)"
if [[ -z "${element_bin}" ]]; then
  echo "ERROR: element-desktop binary not found in tarball" >&2
  exit 1
fi
install -d -m 0755 /usr/lib/element-desktop
cp -a /tmp/element-extract/. /usr/lib/element-desktop/
ln -sf /usr/lib/element-desktop/element-desktop /usr/bin/element-desktop
cat >/usr/share/applications/element-desktop.desktop <<'ELEMENTDESKTOP'
[Desktop Entry]
Name=Element
Comment=Secure messaging and collaboration with Matrix
Exec=/usr/bin/element-desktop %U
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/element;
StartupNotify=true
ELEMENTDESKTOP
element_icon="$(find /usr/lib/element-desktop -type f -name 'icon.png' | head -n1)"
if [[ -n "${element_icon}" ]]; then
  install -d -m 0755 /usr/share/icons/hicolor/512x512/apps
  install -m 0644 "${element_icon}" /usr/share/icons/hicolor/512x512/apps/element-desktop.png
fi
rm -rf /tmp/element-desktop /tmp/element-extract /tmp/element-desktop.tar.gz

# ---------------------------------------------------------------------------
# Vicinae GNOME extension (clipboard and window-management APIs for the
# Vicinae launcher): latest release from GitHub, installed system-wide so
# every user gets it. The extension declares GNOME Shell 46-50; this image
# tracks Fedora 44 (GNOME 51), so the shell-version list is extended after
# extraction to keep the extension active instead of disabled.
# ---------------------------------------------------------------------------
echo "Installing Vicinae GNOME extension..."
VICINAE_EXT_UUID="vicinae@dagimg-dot"
VICINAE_EXT_DIR="/usr/share/gnome-shell/extensions/${VICINAE_EXT_UUID}"
VICINAE_EXT_URL="$(gh_latest_asset_url "vicinaehq/gnome-extension" \
  "vicinae@dagimg-dot\.shell-extension-.*\.zip$")"
rm -rf /tmp/vicinae-ext /tmp/vicinae-ext.zip
retry curl -fL --retry 4 --retry-delay 10 -o /tmp/vicinae-ext.zip "${VICINAE_EXT_URL}"
mkdir -p /tmp/vicinae-ext
unzip -q /tmp/vicinae-ext.zip -d /tmp/vicinae-ext
if [[ ! -f /tmp/vicinae-ext/metadata.json ]]; then
  echo "ERROR: Vicinae extension zip has no metadata.json" >&2
  exit 1
fi
install -d -m 0755 /usr/share/gnome-shell/extensions
rm -rf "${VICINAE_EXT_DIR}"
install -m 0755 -d "${VICINAE_EXT_DIR}"
cp -a /tmp/vicinae-ext/. "${VICINAE_EXT_DIR}/"
if [[ -f "${VICINAE_EXT_DIR}/metadata.json" ]]; then
  python3 - "${VICINAE_EXT_DIR}/metadata.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    meta = json.load(fh)
shell = list(meta.get("shell-version", []))
for ver in ("51", "52"):
    if ver not in shell:
        shell.append(ver)
meta["shell-version"] = shell
with open(path, "w", encoding="utf-8") as fh:
    json.dump(meta, fh, indent=2)
    fh.write("\n")
PY
fi
if [[ -d "${VICINAE_EXT_DIR}/schemas" ]]; then
  for schema in "${VICINAE_EXT_DIR}"/schemas/*.gschema.xml; do
    [[ -f "${schema}" ]] && install -m 0644 "${schema}" \
      /usr/share/glib-2.0/schemas/
  done
  glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
fi
rm -rf /tmp/vicinae-ext /tmp/vicinae-ext.zip

# ---------------------------------------------------------------------------
# GitHub-release fonts (not packaged in Fedora)
# ---------------------------------------------------------------------------
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

# Monaspace (githubnext/monaspace): static TTFs are more compatible than the
# variable release with older tooling.
install_github_fonts "githubnext/monaspace" 'monaspace-static-v[0-9.]+\.zip$' "monaspace"

# Inter (rsms/inter): variable + static weights.
install_github_fonts "rsms/inter" 'Inter-[0-9.]+\.zip$' "inter"

# Lilex (mishamyrt/Lilex)
install_github_fonts "mishamyrt/Lilex" 'Lilex\.zip$' "lilex"

# Fusion JetBrainsMapleMono (SpaceTimee/Fusion-JetBrainsMapleMono):
# XX-XX-XX-XX = default build (ligatures, no hinting, no nerd-font patches).
install_github_fonts "SpaceTimee/Fusion-JetBrainsMapleMono" \
  'JetBrainsMapleMono-XX-XX-XX-XX\.zip$' "fusion-jetbrainsmaplemono"

fc-cache -f >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Post-install smoke checks
# ---------------------------------------------------------------------------
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
check_command gnome-tweaks
check_command mailspring
check_command ferdium
check_command brave-origin
check_command steam
check_command gamescope
check_command mangohud
check_command nicotine

# proton-cachyos: verify the compat tool entry point ships in the system-wide
# Steam compatibility tools directory.
if [[ -x /usr/share/steam/compatibilitytools.d/proton-cachyos/proton ]]; then
  echo "  OK: proton-cachyos (compatibility tool)"
else
  echo "  FAIL: proton-cachyos not installed" >&2
  errors=$((errors + 1))
fi

# Memory management stack: uresourced + low-memory-monitor are RPMs from
# setup-repos-and-rpms.sh (binaries live in /usr/libexec, not on PATH),
# nohang + prelockd are built from source above.
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

# Power management: tuned + tuned-ppd with the max-performance mapping.
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
check_file /etc/dconf/db/local.d/02-vibes-power

# Desktop environment: VKD3D config, Qt log level, persistent shader caches.
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

# Browser/media hardware acceleration configuration.
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

# SELinux gaming/desktop optimization unit.
check_file /etc/systemd/system/vibes-selinux.service
check_file /etc/systemd/system/multi-user.target.wants/vibes-selinux.service

# New cloud-native / dev tooling
for cmd in uv hx yt-dlp gh zoxide bun deno t3code; do
  check_command "$cmd"
done

# Terminal tooling, media apps and utilities added to the image.
for cmd in tmux zellij lollypop rhythmbox fragments trivy \
    element-desktop glance; do
  check_command "$cmd"
done

# Vicinae GNOME extension installed system-wide.
check_file /usr/share/gnome-shell/extensions/vicinae@dagimg-dot/metadata.json

if rpm -q sudo-rs >/dev/null 2>&1; then
  echo "  OK: sudo-rs (rpm)"
else
  echo "  FAIL: sudo-rs not installed" >&2
  errors=$((errors + 1))
fi

# Nix: installed at build time into /var/nix (bind-mounted to /nix at boot).
# Profile symlinks point at /nix/store/..., which only resolves at runtime
# through the mount, so validate the store contents and the profile link
# itself (the nix binary is found inside the store, not via the links).
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

# Font families installed from GitHub releases
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

# Faugus Launcher is an RPM install from a COPR; verify the package rather
# than a PATH binary.
if rpm -q faugus-launcher >/dev/null 2>&1; then
  echo "  OK: faugus-launcher (rpm)"
else
  echo "  FAIL: faugus-launcher not installed" >&2
  errors=$((errors + 1))
fi

# Tearing support from the custom mutter build (MR !3797) must be present in
# the installed library and enabled in the environment.
if grep -aq "tearing" /usr/lib64/libmutter-51.so.0 2>/dev/null; then
  echo "  OK: libmutter tearing support (MR !3797)"
else
  echo "  FAIL: libmutter tearing support not found" >&2
  errors=$((errors + 1))
fi

if grep -aq "MUTTER_DEBUG_EXPERIMENTAL_FEATURES=tearing" \
    /etc/environment.d/90-vibes-desktop-env.conf 2>/dev/null; then
  echo "  OK: mutter tearing experimental feature enabled"
else
  echo "  FAIL: mutter tearing env var not configured" >&2
  errors=$((errors + 1))
fi

# GSConnect is a GNOME Shell extension package; its daemon is not in PATH,
# so verify the RPM itself.
if rpm -q gnome-shell-extension-gsconnect >/dev/null 2>&1; then
  echo "  OK: gnome-shell-extension-gsconnect (rpm)"
else
  echo "  FAIL: gnome-shell-extension-gsconnect not installed" >&2
  errors=$((errors + 1))
fi

check_file /usr/lib64/ladspa/librnnoise_ladspa.so
check_file /etc/systemd/system/multi-user.target.wants/bpftune.service
check_file /etc/environment.d/10-vibes-qt.conf
check_file /etc/dconf/db/local.d/01-vibes-gtk
check_file /usr/share/icons/MoreWaita/index.theme
check_file /usr/share/themes/Yaru/index.theme
check_file /usr/share/icons/Yaru/index.theme

for cmd in lact lmstudio vicinae ananicy-cpp qui helium zen \
    mission-center gear-lever mangojuice; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK (optional): $cmd"
  else
    echo "  SKIP (optional): $cmd"
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} smoke check(s) failed" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
echo "--- Cleaning up ---"
clean_build_artifacts

echo "=== Latest applications installed successfully ==="
