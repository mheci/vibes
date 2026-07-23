#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up repositories and RPM packages ==="

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
  retry "${DNF[@]}" copr enable "$copr"
}

# =============================================================================
# Third-party repositories
# =============================================================================
echo "--- Configuring third-party repositories ---"

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

# =============================================================================
# COPR repositories
# =============================================================================
echo "--- Enabling COPR repositories ---"

# Enable COPR repositories for system-level packages only
# Note: User applications should use Flatpak when available
retry "${DNF[@]}" install --skip-unavailable dnf5-plugins dnf-plugins-core || true

# LACT - GPU monitoring/overclocking (requires kernel access, cannot be Flatpak)
add_copr ilyaz/LACT

# Kernel scheduler tools (require kernel-level access, cannot be Flatpak)
add_copr bieszczaders/kernel-cachyos-addons

# System fonts (require system-level installation)
add_copr che/nerd-fonts

# Faugus Launcher - No Flatpak available on Flathub, COPR only
add_copr faugus/faugus-launcher

# Enable terra repo if present (provided by base image)
if [[ -f /etc/yum.repos.d/terra.repo ]]; then
  sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/terra.repo || true
fi

# Enable Cisco OpenH264 (required for WebRTC video)
"${DNF[@]}" config-manager setopt fedora-cisco-openh264.enabled=1 || true

retry "${DNF[@]}" makecache

# =============================================================================
# Package installation helper
# =============================================================================

# Install packages that are available in enabled repos.
# Packages not found in any repo are skipped with a warning.
#
# Note: per-package `repoquery --available` is deliberate. A bulk-enumeration
# snapshot was tried and reverted (see git history): dnf5 repoquery cannot be
# relied on to enumerate the full available set in the build container (both
# the no-spec and explicit '*' forms return an installed-only subset), and a
# silently-incomplete cache is far worse than the ~1-2 minutes these lookups
# cost. Correctness over speculative speed.
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
    echo "WARN: batch install failed; retrying packages one-by-one" >&2
    for pkg in "${available[@]}"; do
      "${DNF[@]}" install --skip-unavailable "$pkg" || echo "WARN: failed to install optional package: $pkg" >&2
    done
  fi
}

# =============================================================================
# Firefox (RPM, not Flatpak)
# =============================================================================
echo "--- Installing Firefox RPM ---"

# Remove Flatpak Firefox if present (prefer native RPM for codec support)
if command -v flatpak >/dev/null 2>&1; then
  if flatpak list --system 2>/dev/null | grep -q org.mozilla.firefox; then
    flatpak uninstall --system -y org.mozilla.firefox || true
  fi
fi

# Remove conflicting openh264 packages before installing Firefox RPM
if rpm -q openh264 mozilla-openh264 gstreamer1-plugin-openh264 >/dev/null 2>&1; then
  "${DNF[@]}" remove --no-autoremove openh264 mozilla-openh264 gstreamer1-plugin-openh264 || true
fi

retry "${DNF[@]}" install firefox || retry "${DNF[@]}" install --setopt=install_weak_deps=False firefox

# =============================================================================
# NVIDIA drivers and GPU acceleration
# =============================================================================
echo "--- Installing NVIDIA packages ---"

install_available akmod-nvidia-open nvidia-open-dkms nvidia-open-kmod

install_available \
  libva-nvidia-driver nvidia-vaapi-driver nvidia-container-toolkit \
  vulkan-tools egl-utils glx-utils clinfo libva-utils mesa-vulkan-drivers

# =============================================================================
# Desktop applications
# =============================================================================
echo "--- Installing desktop applications ---"

install_available \
  brave-origin \
  kitty umu-launcher pcmanfm-qt \
  code lact scx-scheds scx-tools-git gamemode \
  mangohud gamescope

# =============================================================================
# Multimedia codecs and GStreamer plugins
# =============================================================================
echo "--- Installing multimedia codecs ---"

install_available \
  ffmpeg ffmpeg-libs libavcodec-freeworld mozilla-openh264 \
  gstreamer1-plugin-openh264 gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly gstreamer1-libav gstreamer1-vaapi \
  lame x264 x265 svt-av1-libs rav1e-libs aom dav1d \
  ffmpegthumbnailer \
  heif-pixbuf-loader libheif-freeworld webp-pixbuf-loader libjxl libjxl-utils \
  raw-thumbnailer poppler-utils libgsf tumbler \
  kdegraphics-thumbnailers kio-extras

# =============================================================================
# Fonts
# =============================================================================
echo "--- Installing fonts ---"

install_available \
  nerd-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  google-noto-sans-arabic-fonts google-noto-naskh-arabic-fonts google-noto-kufi-arabic-fonts

# =============================================================================
# Spellcheck dictionaries and language data
# =============================================================================
echo "--- Installing language data ---"

install_available \
  hunspell hunspell-en-US hunspell-ar hyphen-en hyphen-ar aspell aspell-en aspell-ar \
  words autocorr-en autocorr-ar

# =============================================================================
# Audio stack (PipeWire, WirePlumber)
# =============================================================================
echo "--- Installing audio packages ---"

install_available \
  wireplumber pipewire pipewire-utils pipewire-alsa pipewire-pulseaudio pipewire-jack-audio-connection-kit

# =============================================================================
# Build tools (needed for bpftune and other source builds)
# =============================================================================
echo "--- Installing build tools ---"

install_available \
  git make gcc clang llvm bpftool \
  libbpf libbpf-devel libcap libcap-devel libnl3 libnl3-devel \
  python3-docutils elfutils-libelf-devel pkgconf-pkg-config zlib-devel cmake ninja-build

# =============================================================================
# Browser policies and configuration
# =============================================================================
echo "--- Configuring browser policies ---"

# Brave/Chromium: force-install uBlock Origin
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

# Firefox: enable VA-API and WebRender
install -d -m 0755 /usr/lib64/firefox/distribution
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
if [[ -d /usr/lib/firefox/distribution ]]; then
  cp /usr/lib64/firefox/distribution/policies.json /usr/lib/firefox/distribution/policies.json || true
fi

# =============================================================================
# Desktop environment variables (NVIDIA + Qt shader cache)
# =============================================================================
echo "--- Configuring desktop environment variables ---"

cat >/etc/profile.d/90-vibes-desktop-env.sh <<'EOFENV'
# NVIDIA hardware acceleration
export MOZ_ENABLE_WAYLAND=1
export MOZ_WEBRENDER=1
export LIBVA_DRIVER_NAME=nvidia
export VDPAU_DRIVER=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export NVD_BACKEND=direct

# Qt disk shader cache (force-enable for smoother desktop and app launches)
export QSG_DISK_CACHE=1
EOFENV
chmod 0644 /etc/profile.d/90-vibes-desktop-env.sh

install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/90-vibes-desktop-env.conf <<'EOFENV'
MOZ_ENABLE_WAYLAND=1
MOZ_WEBRENDER=1
LIBVA_DRIVER_NAME=nvidia
VDPAU_DRIVER=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
NVD_BACKEND=direct
QSG_DISK_CACHE=1
EOFENV

# =============================================================================
# System services
# =============================================================================
echo "--- Configuring system services ---"

install -d -m 0755 /etc/systemd/system/multi-user.target.wants

# LACT daemon (GPU overclocking/monitoring)
if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
  ln -sf /usr/lib/systemd/system/lactd.service /etc/systemd/system/multi-user.target.wants/lactd.service
fi

# scx_loader (sched_ext scheduler manager)
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
  ln -sf /usr/lib/systemd/system/scx-lavd.service /etc/systemd/system/multi-user.target.wants/scx-lavd.service || true
fi

# =============================================================================
# Cleanup
# =============================================================================
echo "--- Cleaning up ---"
"${DNF[@]}" clean all || true
# Note: /var/cache/libdnf5 is a BuildKit cache mount and cannot be removed.

# Remove build-time /var and /run artifacts flagged by `bootc container lint`
# (var-tmpfiles / nonempty-run-tmp warnings). Logs, dnf metadata, and the
# ldconfig aux-cache are runtime-regenerated state that must not be committed
# to image layers. (/var/lib/flatpak, /var/lib/alternatives stay: they are
# real shipped content — system flatpaks and alternatives DB entries.)
rm -f /var/log/dnf5.log* /var/log/dnf.librepo.log* /var/log/hawkey.log* \
      /var/cache/ldconfig/aux-cache || true
rm -rf /var/lib/dnf /var/cache/dnf /run/dnf || true

echo "=== Repositories and RPM packages configured successfully ==="
