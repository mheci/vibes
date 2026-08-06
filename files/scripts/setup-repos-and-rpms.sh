#!/usr/bin/env bash
# Configure repositories and install RPM packages for the Vibes image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Setting up repositories and RPM packages ==="

# =============================================================================
# Third-party repositories
# =============================================================================
echo "--- Configuring third-party repositories ---"

install -d -m 0755 /etc/yum.repos.d

# Helium Browser repository (COPR)
# Note: Helium is an ungoogled-chromium-based privacy browser.
# COPR: imput/helium, package: helium-bin

# Visual Studio Code repository
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

# Brave Origin browser repository (official, static $basearch - no $releasever)
cat >/etc/yum.repos.d/brave-browser.repo <<'REPO'
[brave-browser]
name=Brave Browser
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
skip_if_unavailable=True
REPO

# =============================================================================
# COPR repositories
# =============================================================================
echo "--- Enabling COPR repositories ---"

retry "${DNF[@]}" install --skip-unavailable dnf5-plugins dnf-plugins-core || true

add_copr() {
  local copr="$1"
  echo "Enabling COPR: ${copr}"
  retry "${DNF[@]}" copr enable "$copr"
}

# Helium Browser (privacy-focused ungoogled-chromium browser)
add_copr imput/helium

# LACT - GPU monitoring/overclocking (kernel access required)
add_copr ilyaz/LACT

# ananicy-cpp (scx-scheds/scx-tools-git were here too, but sched_ext
# schedulers are now built from source in build-scx.sh instead)
add_copr bieszczaders/kernel-cachyos-addons

# CachyOS kernel for Fedora (BORE, HZ=1000, x86_64-v3, PREEMPT_DYNAMIC,
# NO_HZ_FULL, ntsync, sched_ext). The COPR replaces the previous from-source
# kernel build (1h+ on CI runners); installed by setup-cachyos-kernel.sh,
# which also rebuilds the NVIDIA open modules for it.
add_copr bieszczaders/kernel-cachyos

# System fonts (require system-level installation)
# NOTE: che/nerd-fonts does not build for the current Fedora release; pin the
# newest available chroot explicitly (packages are noarch fonts).
retry "${DNF[@]}" copr enable che/nerd-fonts fedora-44-x86_64

# Faugus Launcher (no Flatpak available on Flathub)
add_copr faugus/faugus-launcher

# Yazi terminal file manager
add_copr lihaohong/yazi

# Terra repository is intentionally left disabled. Its GPG signing key is not
# present in the build container on Bazzite, which would cause cascading DNF
# failures on `makecache`. No packages in this image depend on Terra.

# Enable Cisco OpenH264 (required for WebRTC video)
"${DNF[@]}" config-manager setopt fedora-cisco-openh264.enabled=1 || true

retry "${DNF[@]}" makecache

# =============================================================================
# Browser policy: Firefox is intentionally NOT shipped (RPM or Flatpak).
# The Flatpak Firefox that the base image carries is uninstalled from the
# system scope so the image has no Firefox at all.
# =============================================================================
echo "--- Removing Firefox from the base image ---"

if command -v flatpak >/dev/null 2>&1; then
  if flatpak list --system 2>/dev/null | grep -q org.mozilla.firefox; then
    flatpak uninstall --system -y org.mozilla.firefox || true
  fi
fi

if rpm -q firefox >/dev/null 2>&1; then
  "${DNF[@]}" remove --no-autoremove firefox || true
fi

# =============================================================================
# NVIDIA supplementary packages
#
# NOTE: The base Bazzite-nvidia-open image already includes NVIDIA kernel
# drivers. We only install supplementary userspace packages here.
# =============================================================================
echo "--- Installing NVIDIA supplementary packages ---"

install_available \
  libva-nvidia-driver nvidia-vaapi-driver nvidia-container-toolkit \
  vulkan-tools egl-utils glx-utils clinfo libva-utils mesa-vulkan-drivers \
  vulkan-loader vulkan-validation-layers nvidia-settings

# =============================================================================
# Browsers (RPM native only)
# =============================================================================
echo "--- Installing browsers ---"

install_available \
  helium-bin brave-origin

# =============================================================================
# Gaming (Steam, gamescope, mangohud, Faugus)
# GameMode is intentionally NOT installed: it is buggy on this image and
# uresourced (memory tools section) supersedes its CPU/IO priority handling.
# =============================================================================
echo "--- Installing gaming packages ---"

install_available \
  steam steam-devices mangohud

# Remove GameMode if the base image ships it (Bluefin may include it).
if rpm -q gamemode >/dev/null 2>&1; then
  echo "Removing GameMode (buggy on this image; uresourced supersedes it)"
  "${DNF[@]}" remove -y gamemode || true
fi

# =============================================================================
# Memory management (uresourced, low-memory-monitor, nohang, prelockd)
# uresourced gives the active graphical user full CPU/IO priority classes,
# low-memory-monitor warns apps early via D-Bus (warn-only: nohang owns
# killing), nohang replaces systemd-oomd as the desktop OOM guard, and
# prelockd pins commonly used executables/libraries in RAM.
# =============================================================================
echo "--- Installing memory management tools ---"

install_available uresourced low-memory-monitor nohang prelockd

# low-memory-monitor: warn-only, never trigger the kernel OOM killer.
install -d -m 0755 /etc
cat >/etc/low-memory-monitor.conf <<'LMM'
[Configuration]
TriggerKernelOom = false
LMM

# =============================================================================
# Power management (tuned + tuned-ppd)
#
# tuned-ppd is Fedora's power-profiles-daemon replacement: it exposes the
# PPD D-Bus API to desktops and maps the three PPD profiles onto tuned
# profiles via /etc/tuned/ppd.conf. We remap PPD 'performance' to tuned
# 'latency-performance' (CPU governor=performance, PM QoS low-latency lock,
# energy-perf-bias=performance) and make it the default so max performance
# is applied out of the box. GNOME's Power Mode default is likewise set to
# 'performance' via a dconf local default (not locked, so users can still
# switch to balanced/power-saver in Settings).
# =============================================================================
echo "--- Installing power management (tuned + tuned-ppd) ---"

install_available tuned tuned-ppd dconf

install -d -m 0755 /etc/tuned
cat >/etc/tuned/ppd.conf <<'PPDCONF'
[main]
# Default PPD profile (performance -> latency-performance below)
default=performance
battery_detection=true
sysfs_acpi_monitor=true

[profiles]
# PPD = TuneD
power-saver=powersave
balanced=balanced
performance=latency-performance

[battery]
# PPD = TuneD
balanced=balanced-battery
PPDCONF

# GNOME Power Mode default: performance (same pattern as 01-vibes-gtk).
install -d -m 0755 /etc/dconf/db/local.d
cat >/etc/dconf/db/local.d/02-vibes-power <<'DCONF'
[org/gnome/settings-daemon/plugins/power]
power-profile='performance'
DCONF
if [[ ! -f /etc/dconf/profile/user ]]; then
  echo 'user-db:user' >/etc/dconf/profile/user
  echo 'system-db:local' >>/etc/dconf/profile/user
elif ! grep -q 'system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  echo 'system-db:local' >>/etc/dconf/profile/user
fi
dconf update 2>/dev/null || echo "WARN: dconf update failed (GNOME power profile default not compiled)" >&2

# =============================================================================
# Desktop applications
# =============================================================================
echo "--- Installing desktop applications ---"

install_available \
  kitty umu-launcher yazi \
  code lact \
  gamescope \
  ananicy-cpp \
  faugus-launcher \
  tmux lollypop rhythmbox fragments qbittorrent

# =============================================================================
# GNOME desktop additions
# =============================================================================
echo "--- Installing GNOME desktop additions ---"

# GSConnect is installed from the system package: the extension is
# hard-coded to user/local gschema locations that the gnome-extensions
# module cannot populate at build time.
# libgda/libgda-sqlite/gsound: dependencies of the Copyous clipboard manager.
# gnome-menus: runtime dependency of the ArcMenu GNOME Shell extension.
install_available \
  mpv gnome-tweaks \
  libgda libgda-sqlite gsound \
  gnome-shell-extension-gsconnect nautilus-gsconnect \
  gnome-menus

# =============================================================================
# Chat and social clients
# =============================================================================
echo "--- Installing chat clients ---"

# Nicotine+ (Soulseek client) is packaged in the official Fedora repos.
install_available \
  nicotine+

# =============================================================================
# CLI tools (development and cloud-native tooling)
# =============================================================================
echo "--- Installing CLI tools ---"

install_available \
  uv helix yt-dlp gh zoxide just trivy

# =============================================================================
# Just command runner (vjust wrapper for the Vibes justfile)
# =============================================================================
echo "--- Configuring just (vjust wrapper) ---"

if command -v just >/dev/null 2>&1; then
  install -d -m 0755 /usr/share/bash-completion/completions \
    /usr/share/fish/vendor_completions.d
  just --completions bash >/usr/share/bash-completion/completions/just \
    2>/dev/null || true
  just --completions fish >/usr/share/fish/vendor_completions.d/just.fish \
    2>/dev/null || true
fi

cat >/usr/bin/vjust <<'VJUST'
#!/usr/bin/env bash
# vjust - run the Vibes command recipes (wrapper for /usr/share/vibes/justfile)
set -euo pipefail
JUSTFILE="/usr/share/vibes/justfile"
case "${1:-}" in
  list|--list|-l)
    exec just --justfile "${JUSTFILE}" --list --unsorted
    ;;
esac
exec just --justfile "${JUSTFILE}" "$@"
VJUST
chmod 0755 /usr/bin/vjust

# =============================================================================
# sudo-rs (memory-safe sudo implementation)
#
# The Fedora sudo-rs package installs the `sudo-rs`, `visudo-rs` and `su-rs`
# commands alongside the stock sudo; it does not replace /usr/bin/sudo.
# A NOPASSWD policy for the wheel group is shipped as a sudoers.d drop-in
# (see files/system/etc/sudoers.d/99-vibes-wheel-nopasswd).
# =============================================================================
echo "--- Installing sudo-rs ---"

install_available \
  sudo-rs

# Passwordless sudo for the wheel group (shipped here so the drop-in exists
# before install-latest-apps.sh runs its smoke checks; also kept under
# files/system/etc/sudoers.d for reference).
echo "--- Configuring wheel NOPASSWD sudoers drop-in ---"
install -d -m 0755 /etc/sudoers.d
SUDOERS_TMP="/tmp/99-vibes-wheel-nopasswd"
cat >"${SUDOERS_TMP}" <<'SUDOERS'
%wheel ALL=(ALL) NOPASSWD: ALL
SUDOERS
install -m 0440 -o root -g root "${SUDOERS_TMP}" \
  /etc/sudoers.d/99-vibes-wheel-nopasswd
rm -f "${SUDOERS_TMP}"

# =============================================================================
# Yaru theme packs (GTK3/GTK4/shell themes + icon & cursor theme)
# =============================================================================
echo "--- Installing Yaru theme packs ---"

install_available \
  yaru-gtk3-theme yaru-gtk4-theme gnome-shell-theme-yaru yaru-icon-theme

# =============================================================================
# Multimedia codecs and GStreamer plugins
# =============================================================================
echo "--- Installing multimedia codecs ---"

install_available \
  ffmpeg ffmpeg-libs libavcodec-freeworld \
  gstreamer1-plugin-openh264 gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly gstreamer1-libav gstreamer1-vaapi \
  lame x264 x265 svt-av1-libs rav1e-libs aom dav1d \
  ffmpegthumbnailer \
  heif-pixbuf-loader libheif-freeworld webp-pixbuf-loader libjxl libjxl-utils \
  raw-thumbnailer poppler-utils libgsf tumbler

# =============================================================================
# Fonts
#
# Note: Monaspace, Inter, Lilex and Fusion-JetBrainsMapleMono are not packaged
# in Fedora; they are installed from their GitHub releases in
# install-latest-apps.sh. Berkeley Mono is commercial and is intentionally not
# shipped in the image (see README.md).
# =============================================================================
echo "--- Installing fonts ---"

install_available \
  nerd-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  hack-fonts iosevka-fonts \
  ibm-plex-sans-fonts ibm-plex-serif-fonts adobe-source-serif-pro-fonts \
  adobe-source-code-pro-fonts adobe-source-sans-pro-fonts \
  liberation-fonts-all \
  google-noto-sans-arabic-fonts google-noto-naskh-arabic-fonts google-noto-kufi-arabic-fonts

# =============================================================================
# Spellcheck dictionaries and language data
# =============================================================================
echo "--- Installing language data ---"

install_available \
  hunspell hunspell-en-US hunspell-ar hyphen-en hyphen-ar \
  aspell aspell-en aspell-ar words autocorr-en autocorr-ar

# =============================================================================
# Audio stack (PipeWire, WirePlumber)
# =============================================================================
echo "--- Installing audio packages ---"

install_available \
  wireplumber pipewire pipewire-utils pipewire-alsa \
  pipewire-pulseaudio pipewire-jack-audio-connection-kit

# =============================================================================
# Build tools and core utilities (needed for bpftune, theme/app installs)
# =============================================================================
echo "--- Installing build tools and core utilities ---"

install_available \
  git make gcc clang llvm bpftool nodejs npm jq unzip rsync file which \
  libbpf libbpf-devel libcap libcap-devel libnl3 libnl3-devel \
  python3-docutils elfutils-libelf-devel pkgconf-pkg-config \
  zlib-devel ninja-build tar gzip xz

# =============================================================================
# Browser policies and configuration
# =============================================================================
echo "--- Configuring browser policies ---"

# Chromium-family browsers (Chromium, Helium, Brave Origin): enforce VA-API
# hardware video decode. Chromium disables VA-API on NVIDIA GPUs by default
# (chromium issue 40285654), so VaapiOnNvidiaGPUs + VaapiIgnoreDriverChecks
# are required; libva-nvidia-driver is installed above. Applied three ways:
# managed policies (cannot be overridden by the browser) in every policy
# directory the shipped browsers read, plus the global flags file read by
# Fedora-style chromium wrappers, plus per-user flags files in /etc/skel for
# the documented <browser>-flags.conf locations.
for policy_dir in /etc/opt/chrome/policies/managed /etc/chromium/policies/managed /etc/brave/policies/managed; do
  install -d -m 0755 "$policy_dir"
  cat >"${policy_dir}/vibes-hw-accel.json" <<'JSON'
{
  "CommandLineFlagPolicyEnforced": [
    "--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecoder,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs",
    "--ignore-gpu-blocklist"
  ],
  "HardwareAccelerationModeEnabled": true
}
JSON
done
echo "Chromium-family VA-API policies written"

cat >/etc/chromium-flags.conf <<'FLAGS'
# VA-API hardware video decode (see wiki.cachyos.org: enabling hardware
# acceleration in Google Chrome); libva-nvidia-driver provides NVDEC via
# VA-API on NVIDIA.
--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecoder,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs
--ignore-gpu-blocklist
FLAGS

install -d -m 0755 /etc/skel/.config
for flags_conf in chromium-flags.conf ungoogled-chromium-flags.conf brave-origin-flags.conf; do
  cat >"/etc/skel/.config/${flags_conf}" <<'FLAGS'
--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecoder,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs
--ignore-gpu-blocklist
FLAGS
done

# =============================================================================
# Media player configuration (mpv)
# =============================================================================
echo "--- Configuring media players ---"

# mpv: hardware video decode via VA-API (NVDEC on NVIDIA through
# libva-nvidia-driver), with safe software fallback.
install -d -m 0755 /etc/mpv
cat >/etc/mpv/mpv.conf <<'MPVCONF'
# Hardware video decoding (auto-safe: prefers VA-API, falls back to
# software when the driver does not support the codec).
hwdec=auto-safe
MPVCONF

# =============================================================================
# Desktop environment variables (NVIDIA + Qt shader cache)
# =============================================================================
echo "--- Configuring desktop environment variables ---"

install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/90-vibes-desktop-env.conf <<'EOFENV'
# NVIDIA hardware acceleration
MOZ_ENABLE_WAYLAND=1
MOZ_WEBRENDER=1
LIBVA_DRIVER_NAME=nvidia
VDPAU_DRIVER=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
NVD_BACKEND=direct

# vkd3d-proton (Direct3D 12 -> Vulkan, used by proton-cachyos): use the
# descriptor-heap allocation mode instead of descriptor-array emulation
# (lower memory churn in D3D12 titles).
VKD3D_CONFIG=descriptor_heap

# Qt logging: warnings and above only. Silences the Qt debug/info flood
# (Qt Quick, QWebEngine, KDE frameworks) in the journal and on stdout.
QT_LOGGING_RULES=*.debug=false;*.info=false

# Persistent shader caches: anchor every toolkit's disk cache to the
# persistent per-user cache directory so nothing lands in volatile
# locations ($XDG_RUNTIME_DIR, /tmp) and caches survive reboots.
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
__GL_SHADER_DISK_CACHE_PATH=${XDG_CACHE_HOME}/nvidia/GLCache
MESA_SHADER_CACHE_DIR=${XDG_CACHE_HOME}/mesa_shader_cache
DXVK_STATE_CACHE_PATH=${XDG_CACHE_HOME}/dxvk-cache

# Qt disk shader cache (smoother desktop and application launches)
QSG_DISK_CACHE=1

# NVIDIA shader disk cache: raise the 256 MiB default cap to 100 GiB and skip
# the periodic cleanup pass (both prevent shader recompilation stutter in
# large titles; a cap keeps the cache bounded).
__GL_SHADER_DISK_CACHE=1
__GL_SHADER_DISK_CACHE_SIZE=107374182400
__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1

# Mutter MR !3797: enable tearing/async page-flip support (custom build)
MUTTER_DEBUG_EXPERIMENTAL_FEATURES=tearing,variable-refresh-rate
EOFENV

# =============================================================================
# System services
# =============================================================================
echo "--- Configuring system services ---"

install -d -m 0755 /etc/systemd/system/multi-user.target.wants

# LACT daemon (GPU overclocking/monitoring)
if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
  ln -sf /usr/lib/systemd/system/lactd.service \
    /etc/systemd/system/multi-user.target.wants/lactd.service
fi

# ananicy-cpp (auto-nice daemon for process priority management)
if command -v ananicy-cpp >/dev/null 2>&1; then
  ananicy_service=""
  for candidate in /usr/lib/systemd/system/ananicy-cpp.service \
                   /lib/systemd/system/ananicy-cpp.service; do
    if [[ -f "$candidate" ]]; then
      ananicy_service="$candidate"
      break
    fi
  done
  if [[ -n "$ananicy_service" ]]; then
    ln -sf "$ananicy_service" \
      /etc/systemd/system/multi-user.target.wants/ananicy-cpp.service
    echo "ananicy-cpp service enabled"
  fi
fi

# Memory management services (uresourced, low-memory-monitor). Enabling
# follows the symlink pattern used above: containers cannot run systemctl,
# so unit activation is a .wants symlink. nohang and prelockd are built from
# source in install-latest-apps.sh, which enables their units there.
for unit in uresourced.service low-memory-monitor.service; do
  for candidate in "/usr/lib/systemd/system/${unit}" "/lib/systemd/system/${unit}"; do
    if [[ -f "$candidate" ]]; then
      ln -sf "$candidate" "/etc/systemd/system/multi-user.target.wants/${unit}"
      echo "${unit} service enabled"
      break
    fi
  done
done

# nohang replaces systemd-oomd as the desktop low-memory guard; mask it so it
# can never come back on package updates (same /dev/null trick as
# systemctl mask, which is unavailable in the container).
install -d -m 0755 /etc/systemd/system
if [[ -e /usr/lib/systemd/system/systemd-oomd.service ]]; then
  ln -sf /dev/null /etc/systemd/system/systemd-oomd.service
  echo "systemd-oomd masked (nohang replaces it)"
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
  ln -sf /usr/lib/systemd/system/scx_loader.service \
    /etc/systemd/system/multi-user.target.wants/scx_loader.service
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
  ln -sf /usr/lib/systemd/system/scx-lavd.service \
    /etc/systemd/system/multi-user.target.wants/scx-lavd.service || true
fi

# Power management (tuned + tuned-ppd)
for unit in tuned.service tuned-ppd.service; do
  for candidate in "/usr/lib/systemd/system/${unit}" "/lib/systemd/system/${unit}"; do
    if [[ -f "$candidate" ]]; then
      ln -sf "$candidate" "/etc/systemd/system/multi-user.target.wants/${unit}"
      echo "${unit} enabled"
      break
    fi
  done
done

# =============================================================================
# SELinux desktop/gaming tuning
#
# Fedora ships SELinux enforcing. The desktop session is unconfined_t, but
# Steam/Proton games need execmod on some third-party libraries; the SUSE
# security team's Steam gaming guide (and the Fedora gaming SCM) recommend
# enabling the selinuxuser_execmod boolean. setsebool cannot run inside the
# build container, so a oneshot unit applies it at boot (idempotent and
# skipped when SELinux is disabled).
# =============================================================================
echo "--- Configuring SELinux tuning ---"

install -d -m 0755 /etc/systemd/system
cat >/etc/systemd/system/vibes-selinux.service <<'UNIT'
[Unit]
Description=Vibes SELinux desktop/gaming optimization
Documentation=https://github.com/mheci/vibes
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Skips cleanly when SELinux is disabled (e.g. custom kernels).
ConditionPathIsReadWrite=/sys/fs/selinux
ExecStart=/usr/sbin/setsebool -P selinuxuser_execmod on

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/vibes-selinux.service \
  /etc/systemd/system/multi-user.target.wants/vibes-selinux.service
echo "vibes-selinux.service enabled"

# =============================================================================
# Firewall verification
#
# Fedora's FedoraWorkstation zone opens 1025-65535 (tcp+udp), which covers
# Steam (UDP 27000-27100, TCP 27015-27050...), GSConnect/KDE Connect
# (1714-1764 tcp+udp), BitTorrent, DLNA and media servers. Verify the zone
# file shipped by firewalld so nothing in the image breaks that default.
# =============================================================================
echo "--- Verifying firewall policy ---"

if [[ -f /usr/lib/firewalld/zones/FedoraWorkstation.xml ]] \
  && grep -q '1025-65535' /usr/lib/firewalld/zones/FedoraWorkstation.xml; then
  echo "OK: FedoraWorkstation zone opens 1025-65535 (Steam/GSConnect/torrents/media pass)"
else
  echo "WARN: FedoraWorkstation zone with 1025-65535 not found; verify the firewall" >&2
  echo "      does not block Steam, GSConnect, torrents or media servers" >&2
fi

# =============================================================================
# Cleanup
# =============================================================================
echo "--- Cleaning up ---"
clean_build_artifacts

echo "=== Repositories and RPM packages configured successfully ==="
