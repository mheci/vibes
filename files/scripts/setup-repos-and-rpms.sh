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

# shellcheck disable=SC2317,SC2329
on_error() {
  local exit_code=$?
  local line_no=$1
  die "setup-repos-and-rpms.sh failed at line ${line_no} with exit code ${exit_code}"
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

repo_exists() {
  local repo_id="$1"
  "${DNF[@]}" repolist --all "$repo_id" >/dev/null 2>&1
}

enable_repo_if_present() {
  local repo_id="$1"
  if repo_exists "$repo_id"; then
    retry "${DNF[@]}" config-manager setopt "${repo_id}.enabled=1"
  else
    warn "repository '${repo_id}' not present; skipping enable step"
  fi
}

add_copr() {
  local copr="$1"
  log "Enabling COPR: ${copr}"
  retry "${DNF[@]}" copr enable "$copr"
}

package_available_or_installed() {
  local pkg="$1"
  rpm -q "$pkg" >/dev/null 2>&1 || "${DNF[@]}" repoquery --available "$pkg" >/dev/null 2>&1
}

install_required_packages() {
  local pkg missing=0
  for pkg in "$@"; do
    if ! package_available_or_installed "$pkg"; then
      warn "required package unavailable in enabled repos: $pkg"
      missing=1
    fi
  done

  (( missing == 0 )) || die "one or more required packages are unavailable"
  retry "${DNF[@]}" install "$@"
}

install_optional_packages() {
  local pkg available=()
  for pkg in "$@"; do
    if package_available_or_installed "$pkg"; then
      available+=("$pkg")
    else
      warn "optional package unavailable in enabled repos, skipping: $pkg"
    fi
  done

  if (( ${#available[@]} > 0 )); then
    if ! retry "${DNF[@]}" install "${available[@]}"; then
      warn "optional package batch install failed; retrying one-by-one"
      for pkg in "${available[@]}"; do
        if ! "${DNF[@]}" install "$pkg"; then
          warn "failed to install optional package: $pkg"
        fi
      done
    fi
  fi
}

remove_if_installed() {
  local installed=() pkg
  for pkg in "$@"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
      installed+=("$pkg")
    fi
  done

  if (( ${#installed[@]} > 0 )); then
    retry "${DNF[@]}" remove --no-autoremove "${installed[@]}"
  fi
}

install -d -m 0755 /etc/yum.repos.d

# Official Brave RPM repository.
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

# Official Terra repository configuration for atomic Fedora derivatives.
retry curl -fsSL -o /etc/yum.repos.d/terra.repo \
  https://raw.githubusercontent.com/terrapkg/subatomic-repos/main/terra.repo

# DNF plugins are required for config-manager and COPR enablement.
install_required_packages jq curl git
if command -v dnf5 >/dev/null 2>&1; then
  install_required_packages dnf5-plugins
else
  install_required_packages dnf-plugins-core
fi

# Terra release packages should be installed from Terra itself so repo migrations are handled upstream.
retry "${DNF[@]}" install --nogpgcheck terra-release
install_optional_packages terra-release-extras
enable_repo_if_present terra
enable_repo_if_present terra-extras

# COPRs and adjacent repos for image-specific software.
add_copr faugus/faugus-launcher
add_copr ilyaz/LACT
add_copr bieszczaders/kernel-cachyos-addons
add_copr che/nerd-fonts

# Refresh metadata after adding repositories.
enable_repo_if_present fedora-cisco-openh264
retry "${DNF[@]}" makecache

# Remove Flatpak Firefox if present so the RPM replacement is authoritative.
if command -v flatpak >/dev/null 2>&1; then
  if flatpak list --system --app --columns=application | grep -qx 'org.mozilla.firefox'; then
    retry flatpak uninstall --system -y org.mozilla.firefox
  fi
fi

# Firefox RPM can conflict with preinstalled OpenH264 providers on atomic bases.
remove_if_installed openh264 mozilla-openh264 gstreamer1-plugin-openh264
retry "${DNF[@]}" install firefox

# The image already tracks the latest Bazzite NVIDIA Open base. These layered packages ensure
# the matching userspace and rebuild tooling are present as the base updates.
install_required_packages \
  akmod-nvidia-open \
  nvidia-container-toolkit \
  nvidia-modprobe \
  nvidia-settings
install_optional_packages nvidia-open-dkms nvidia-open-kmod nvidia-vaapi-driver

# Core desktop, gaming, media, codec, theming, and build dependencies.
install_required_packages \
  brave-origin \
  code \
  ffmpeg \
  ffmpeg-libs \
  ffmpegthumbnailer \
  gamescope \
  gamemode \
  gstreamer1-libav \
  gstreamer1-plugin-openh264 \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good \
  gstreamer1-plugins-ugly \
  gstreamer1-vaapi \
  gtk-murrine-engine \
  hicolor-icon-theme \
  hunspell \
  hunspell-ar \
  hunspell-en-US \
  hyphen-ar \
  hyphen-en \
  inter-fonts \
  jetbrains-mono-fonts \
  kio-extras \
  kitty \
  kvantum \
  kvantum-qt5 \
  libappstream-glib \
  libavcodec-freeworld \
  libbpf \
  libbpf-devel \
  libcap \
  libcap-devel \
  libepoxy-devel \
  libgsf \
  libheif-freeworld \
  libjxl \
  libjxl-utils \
  libnl3 \
  libnl3-devel \
  libva-nvidia-driver \
  libva-utils \
  make \
  mangohud \
  mesa-dri-drivers \
  mesa-vulkan-drivers \
  mozilla-openh264 \
  pipewire \
  pipewire-alsa \
  pipewire-jack-audio-connection-kit \
  pipewire-pulseaudio \
  pipewire-utils \
  pkgconf-pkg-config \
  qt5ct \
  qt6ct \
  sassc \
  scx-scheds \
  scx-tools-git \
  steam \
  steam-devices \
  umu-launcher \
  unzip \
  vulkan-tools \
  wireplumber \
  words \
  x264 \
  x265 \
  xdg-desktop-portal-kde

install_optional_packages \
  aom \
  adobe-source-code-pro-fonts \
  appstream \
  aspell \
  aspell-ar \
  aspell-en \
  autocorr-ar \
  autocorr-en \
  bpftool \
  cascadia-code-fonts \
  clang \
  clinfo \
  cmake \
  dav1d \
  egl-utils \
  elfutils-libelf-devel \
  faugus-launcher \
  fira-code-fonts \
  gcc \
  glx-utils \
  google-noto-color-emoji-fonts \
  google-noto-kufi-arabic-fonts \
  google-noto-naskh-arabic-fonts \
  google-noto-sans-arabic-fonts \
  goverlay \
  heif-pixbuf-loader \
  heroic \
  heroic-games-launcher \
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
  kdegraphics-thumbnailers \
  kwin-devel \
  lact \
  lame \
  liberation-sans-fonts \
  liberation-serif-fonts \
  llvm \
  lutris \
  nerd-fonts \
  ninja-build \
  opi \
  pcmanfm-qt \
  poppler-utils \
  protontricks \
  python3-docutils \
  qt5-qtquickcontrols2-devel \
  rav1e-libs \
  raw-thumbnailer \
  svt-av1-libs \
  tumbler \
  vkBasalt \
  webp-pixbuf-loader \
  winetricks \
  zlib-devel \
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
  "cmake(Qt5UiTools)"

# Brave + uBlock Origin policy. This gives “Brave + Origin” behavior without mutating user profiles.
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
cp /usr/lib64/firefox/distribution/policies.json /usr/lib/firefox/distribution/policies.json

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

install -d -m 0755 /etc/systemd/system/multi-user.target.wants
if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
  ln -sf /usr/lib/systemd/system/lactd.service /etc/systemd/system/multi-user.target.wants/lactd.service
fi

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

"${DNF[@]}" clean all
rm -rf /var/cache/dnf /var/cache/libdnf5
