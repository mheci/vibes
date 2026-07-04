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

add_copr() {
  local copr="$1"
  echo "Enabling COPR: ${copr}"
  retry "${DNF[@]}" copr enable "$copr" || {
    echo "WARN: failed to enable COPR ${copr}, continuing anyway" >&2
    return 0
  }
}

# Official Brave RPM repository (provides brave-origin and brave-browser).
install -d -m 0755 /etc/yum.repos.d
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

# Waterfox RPM repo.
cat >/etc/yum.repos.d/waterfox.repo <<'REPO'
[waterfox]
name=Waterfox
baseurl=https://repo.waterfox.net/fedora/$releasever/
enabled=1
gpgcheck=1
gpgkey=https://repo.waterfox.net/key.asc
skip_if_unavailable=True
REPO

# Ensure DNF COPR/config-manager plugins are available.
retry "${DNF[@]}" install --skip-unavailable dnf5-plugins dnf-plugins-core || true

# COPRs for requested/adjacent software.
add_copr faugus/faugus-launcher
add_copr ilyaz/LACT
add_copr bieszczaders/kernel-cachyos-addons
add_copr che/nerd-fonts

# Terra is already present on Bazzite; ensure it is enabled for vicinae and friends.
if [[ -f /etc/yum.repos.d/terra.repo ]]; then
  sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/terra.repo || true
fi

# Refresh metadata after adding repositories.
"${DNF[@]}" config-manager setopt fedora-cisco-openh264.enabled=1 || true
retry "${DNF[@]}" makecache

# Core packages requested by the image owner. We first query availability to avoid Fedora/latest
# repo churn bricking autonomous builds when optional package names move or disappear.
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

# Remove flatpak Firefox if present so the RPM replacement is the only Firefox.
if command -v flatpak >/dev/null 2>&1; then
  flatpak uninstall --system -y org.mozilla.firefox >/dev/null 2>&1 || true
fi

# Firefox RPM can conflict with preinstalled OpenH264 providers on atomic bases; install it first
# without those providers present, then install codecs opportunistically below.
"${DNF[@]}" remove --no-autoremove openh264 mozilla-openh264 gstreamer1-plugin-openh264 || true
retry "${DNF[@]}" install firefox || retry "${DNF[@]}" install --setopt=install_weak_deps=False firefox

# Install Waterfox from its RPM repo (configured above).
install_available waterfox || true

# Always pull the latest NVIDIA Open kernel module tooling so akmods rebuilds stay current.
# Bazzite base already ships the open driver; this ensures the akmod layer is present for updates.
install_available akmod-nvidia-open nvidia-open-dkms nvidia-open-kmod || true

install_available \
  brave-origin \
  faugus-launcher kitty umu-launcher pcmanfm-qt \
  code lact scx-scheds scx-tools-git gamemode \
  libva-nvidia-driver nvidia-vaapi-driver nvidia-container-toolkit \
  vulkan-tools egl-utils glx-utils clinfo libva-utils mesa-vulkan-drivers \
  git make gcc clang llvm bpftool libbpf libbpf-devel libcap libcap-devel libnl3 libnl3-devel python3-docutils elfutils-libelf-devel pkgconf-pkg-config zlib-devel cmake ninja-build \
  ffmpeg ffmpeg-libs libavcodec-freeworld mozilla-openh264 \
  gstreamer1-plugin-openh264 gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly gstreamer1-libav gstreamer1-vaapi \
  lame x264 x265 svt-av1-libs rav1e-libs aom dav1d \
  ffmpegthumbnailer kdegraphics-thumbnailers kio-extras \
  heif-pixbuf-loader libheif-freeworld webp-pixbuf-loader libjxl libjxl-utils \
  raw-thumbnailer poppler-utils libgsf tumbler \
  hunspell hunspell-en-US hunspell-ar hyphen-en hyphen-ar aspell aspell-en aspell-ar \
  words autocorr-en autocorr-ar \
  nerd-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  google-noto-sans-arabic-fonts google-noto-naskh-arabic-fonts google-noto-kufi-arabic-fonts \
  wireplumber pipewire pipewire-utils pipewire-alsa pipewire-pulseaudio pipewire-jack-audio-connection-kit \
  mangohud gamescope

  # Vicinae from Terra (Bazzite already carries Terra; enabled above).
  # NOTE: Terra's vicinae RPM depends on qt6-qtbase-gui -> mesa-libEGL,
  # which is excluded on Bazzite. Skip RPM install here; AppImage used instead.
  # install_available vicinae || true

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
