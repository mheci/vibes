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

set_repo_enabled() {
  local repo_id="$1"
  local state="$2"
  "${DNF[@]}" config-manager setopt "${repo_id}.enabled=${state}" || true
}

add_copr() {
  local copr="$1"
  echo "Enabling COPR: ${copr}"
  retry "${DNF[@]}" copr enable "$copr" || {
    echo "WARN: failed to enable COPR ${copr}, continuing anyway" >&2
    return 0
  }
}

install_available() {
  local pkgs=("$@") available=() pkg
  for pkg in "${pkgs[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1 || "${DNF[@]}" repoquery --available "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      echo "WARN: package unavailable in enabled repos, skipping: $pkg" >&2
    fi
  done

  if (( ${#available[@]} == 0 )); then
    return 0
  fi

  if ! retry "${DNF[@]}" install "${available[@]}"; then
    echo "WARN: batch package install failed; retrying packages one-by-one without long retries" >&2
    for pkg in "${available[@]}"; do
      "${DNF[@]}" install "$pkg" || echo "WARN: failed to install optional package: $pkg" >&2
    done
  fi
}

install -d -m 0755 /etc/yum.repos.d

# Official Brave RPM repository (provides brave-origin and brave-browser).
cat >/etc/yum.repos.d/brave-browser.repo <<'REPO'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
repo_gpgcheck=1
skip_if_unavailable=True
REPO

# Official Microsoft VS Code RPM repository.
cat >/etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
skip_if_unavailable=True
REPO

# Waterfox RPM repository.
cat >/etc/yum.repos.d/waterfox.repo <<'REPO'
[waterfox]
name=Waterfox
baseurl=https://repo.waterfox.net/fedora/$releasever/
enabled=1
gpgcheck=1
gpgkey=https://repo.waterfox.net/key.asc
skip_if_unavailable=True
REPO

# Configure Terra from the official subatomic repo file so atomic installs stay aligned
# with current upstream guidance. Keep the stable main repo and extras enabled. We do not
# force Terra multimedia because upstream currently documents it as unstable/WIP.
retry curl -fsSL -o /etc/yum.repos.d/terra.repo \
  https://raw.githubusercontent.com/terrapkg/subatomic-repos/main/terra.repo
retry "${DNF[@]}" install --nogpgcheck terra-release || true
install_available terra-release-extras || true
set_repo_enabled terra 1
set_repo_enabled terra-extras 1

# Ensure DNF plugins are available before further repo manipulation.
retry "${DNF[@]}" install --skip-unavailable dnf5-plugins dnf-plugins-core || true

# COPRs and adjacent repos for image-specific software.
add_copr faugus/faugus-launcher
add_copr ilyaz/LACT
add_copr bieszczaders/kernel-cachyos-addons
add_copr che/nerd-fonts

# Refresh metadata after adding repositories.
set_repo_enabled fedora-cisco-openh264 1
retry "${DNF[@]}" makecache

# Remove flatpak Firefox if present so the RPM replacement is the only Firefox.
if command -v flatpak >/dev/null 2>&1; then
  flatpak uninstall --system -y org.mozilla.firefox >/dev/null 2>&1 || true
fi

# Firefox RPM can conflict with preinstalled OpenH264 providers on atomic bases; install it first
# without those providers present, then install codecs and the rest of the stack afterwards.
"${DNF[@]}" remove --no-autoremove openh264 mozilla-openh264 gstreamer1-plugin-openh264 || true
retry "${DNF[@]}" install firefox || retry "${DNF[@]}" install --setopt=install_weak_deps=False firefox

# Direct repositories / latest channels.
install_available waterfox || true

# Latest NVIDIA user space and akmods. The image already tracks the latest Bazzite NVIDIA Open
# base; these packages ensure the layered userspace and rebuild tooling stay current as well.
install_available \
  akmod-nvidia-open \
  nvidia-open-dkms \
  nvidia-open-kmod \
  nvidia-container-toolkit \
  nvidia-modprobe \
  nvidia-settings || true

# Core desktop, gaming, media, codec, theming, and build dependencies.
install_available \
  brave-origin \
  faugus-launcher \
  gamemode \
  gamescope \
  goverlay \
  heroic \
  heroic-games-launcher \
  kitty \
  lact \
  lutris \
  mangohud \
  opi \
  pcmanfm-qt \
  protontricks \
  scx-scheds \
  scx-tools-git \
  steam \
  steam-devices \
  umu-launcher \
  vkBasalt \
  winetricks \
  xdg-desktop-portal-kde \
  code \
  clinfo \
  egl-utils \
  glx-utils \
  libva-utils \
  libva-nvidia-driver \
  mesa-dri-drivers \
  mesa-vulkan-drivers \
  nvidia-vaapi-driver \
  vulkan-tools \
  appstream \
  bpftool \
  clang \
  cmake \
  elfutils-libelf-devel \
  gcc \
  git \
  jq \
  libappstream-glib \
  libbpf \
  libbpf-devel \
  libepoxy-devel \
  libcap \
  libcap-devel \
  libnl3 \
  libnl3-devel \
  llvm \
  make \
  ninja-build \
  pkgconf-pkg-config \
  python3-docutils \
  sassc \
  "cmake(KDecoration3)" \
  "cmake(KF5ConfigWidgets)" \
  "cmake(KF5CoreAddons)" \
  "cmake(KF5FrameworkIntegration)" \
  "cmake(KF5GlobalAccel)" \
  "cmake(KF5GuiAddons)" \
  "cmake(KF5I18n)" \
  "cmake(KF5IconThemes)" \
  "cmake(KF5Init)" \
  "cmake(KF5KIO)" \
  "cmake(KF5WindowSystem)" \
  "cmake(Qt5Core)" \
  "cmake(Qt5DBus)" \
  "cmake(Qt5Gui)" \
  "cmake(Qt5UiTools)" \
  kf5-kcmutils-devel \
  kf5-kirigami2-devel \
  kf5-kpackage-devel \
  kf6-frameworkintegration-devel \
  kf6-kcmutils-devel \
  kf6-kcolorscheme-devel \
  kf6-kiconthemes-devel \
  kf6-kguiaddons-devel \
  kf6-ki18n-devel \
  kf6-kirigami-devel \
  kwin-devel \
  qt5-qtquickcontrols2-devel \
  unzip \
  zlib-devel \
  ffmpeg \
  ffmpeg-libs \
  ffmpegthumbnailer \
  gstreamer1-libav \
  gstreamer1-plugin-openh264 \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good \
  gstreamer1-plugins-ugly \
  gstreamer1-vaapi \
  heif-pixbuf-loader \
  kio-extras \
  kdegraphics-thumbnailers \
  lame \
  libavcodec-freeworld \
  libgsf \
  libheif-freeworld \
  libjxl \
  libjxl-utils \
  mozilla-openh264 \
  poppler-utils \
  raw-thumbnailer \
  rav1e-libs \
  svt-av1-libs \
  tumbler \
  webp-pixbuf-loader \
  x264 \
  x265 \
  aom \
  dav1d \
  aspell \
  aspell-ar \
  aspell-en \
  autocorr-ar \
  autocorr-en \
  hunspell \
  hunspell-ar \
  hunspell-en-US \
  hyphen-ar \
  hyphen-en \
  words \
  adobe-source-code-pro-fonts \
  cascadia-code-fonts \
  fira-code-fonts \
  google-noto-color-emoji-fonts \
  google-noto-kufi-arabic-fonts \
  google-noto-naskh-arabic-fonts \
  google-noto-sans-arabic-fonts \
  inter-fonts \
  jetbrains-mono-fonts \
  liberation-sans-fonts \
  liberation-serif-fonts \
  nerd-fonts \
  pipewire \
  pipewire-alsa \
  pipewire-jack-audio-connection-kit \
  pipewire-pulseaudio \
  pipewire-utils \
  wireplumber \
  gtk-murrine-engine \
  hicolor-icon-theme \
  kvantum \
  kvantum-qt5 \
  qt5ct \
  qt6ct

# Vicinae from Terra is not used directly because the current RPM conflicts with the
# Bazzite base's mesa-libEGL exclusions. We keep Terra configured and install Vicinae
# from the upstream AppImage in the direct-source installer step instead.

# Brave + uBlock Origin policy. This gives "Brave + Origin" behavior without mutating user profiles.
install -d -m 0755 /etc/brave/policies/managed /etc/chromium/policies/managed
cat >/etc/brave/policies/managed/10-ublock-origin.json <<'JSON'
{
  "ExtensionInstallForcelist": [
    "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx"
  ],
  "HardwareAccelerationModeEnabled": true
}
JSON
cp /etc/brave/policies/managed/10-ublock-origin.json /etc/chromium/policies/managed/10-ublock-origin.json

# Firefox RPM policy: hardware acceleration enabled where supported, spellchecking for English and Arabic.
install -d -m 0755 /usr/lib64/firefox/distribution /usr/lib/firefox/distribution
cat >/usr/lib64/firefox/distribution/policies.json <<'JSON'
{
  "policies": {
    "Preferences": {
      "media.ffmpeg.vaapi.enabled": { "Value": true, "Status": "default" },
      "media.hardware-video-decoding.force-enabled": { "Value": true, "Status": "default" },
      "gfx.webrender.all": { "Value": true, "Status": "default" },
      "spellchecker.dictionary": { "Value": "en-US,ar", "Status": "default" }
    }
  }
}
JSON
cp /usr/lib64/firefox/distribution/policies.json /usr/lib/firefox/distribution/policies.json || true

# NVIDIA/Wayland acceleration defaults. These are system defaults only; users can override them.
cat >/etc/profile.d/90-vibes-nvidia-accel.sh <<'EOFENV'
# NVIDIA Open driver + Wayland/VAAPI acceleration defaults for Vibes.
export MOZ_ENABLE_WAYLAND=1
export MOZ_WEBRENDER=1
export LIBVA_DRIVER_NAME=nvidia
export VDPAU_DRIVER=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export NVD_BACKEND=direct
EOFENV
chmod 0644 /etc/profile.d/90-vibes-nvidia-accel.sh

# Also set the same for shells that source /etc/environment.d
install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/90-vibes-nvidia-accel.conf <<'EOFENV'
MOZ_ENABLE_WAYLAND=1
MOZ_WEBRENDER=1
LIBVA_DRIVER_NAME=nvidia
VDPAU_DRIVER=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
NVD_BACKEND=direct
EOFENV

# LACT daemon: enable if RPM installed a service.
install -d -m 0755 /etc/systemd/system/multi-user.target.wants
if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
  ln -sf /usr/lib/systemd/system/lactd.service /etc/systemd/system/multi-user.target.wants/lactd.service
fi

# scx_loader default config: LAVD in Gaming mode maps to --performance in current scx_loader.
install -d -m 0755 /etc/scx_loader
cat >/etc/scx_loader/config.toml <<'TOML'
default_sched = "scx_lavd"
default_mode = "Gaming"

[scheds.scx_lavd]
gaming_mode = ["--performance"]
lowlatency_mode = ["--performance"]
auto_mode = ["--autopilot"]
powersave_mode = ["--powersave"]
server_mode = ["--autopilot"]
TOML

if [[ -f /usr/lib/systemd/system/scx_loader.service ]]; then
  ln -sf /usr/lib/systemd/system/scx_loader.service /etc/systemd/system/multi-user.target.wants/scx_loader.service
elif command -v scx_lavd >/dev/null 2>&1; then
  cat >/usr/lib/systemd/system/scx-lavd.service <<'UNIT'
[Unit]
Description=scx_lavd sched_ext scheduler in performance mode
Documentation=https://github.com/sched-ext/scx
After=multi-user.target
ConditionPathExists=/sys/kernel/sched_ext

[Service]
Type=simple
ExecStart=/usr/bin/scx_lavd --performance
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  ln -sf /usr/lib/systemd/system/scx-lavd.service /etc/systemd/system/multi-user.target.wants/scx-lavd.service
fi

# Clean caches to keep the final image smaller.
"${DNF[@]}" clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
