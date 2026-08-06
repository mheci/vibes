#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Setting up repositories and RPM packages ==="

echo "--- Configuring third-party repositories ---"

install -d -m 0755 /etc/yum.repos.d


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

cat >/etc/yum.repos.d/brave-browser.repo <<'REPO'
[brave-browser]
name=Brave Browser
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
skip_if_unavailable=True
REPO

echo "--- Enabling COPR repositories ---"

retry "${DNF[@]}" install --skip-unavailable dnf5-plugins dnf-plugins-core || true

add_copr() {
  local copr="$1"
  echo "Enabling COPR: ${copr}"
  retry "${DNF[@]}" copr enable "$copr"
}

add_copr imput/helium

add_copr ilyaz/LACT

add_copr bieszczaders/kernel-cachyos-addons

add_copr bieszczaders/kernel-cachyos

retry "${DNF[@]}" copr enable che/nerd-fonts fedora-44-x86_64

add_copr faugus/faugus-launcher

add_copr lihaohong/yazi


"${DNF[@]}" config-manager setopt fedora-cisco-openh264.enabled=1 || true

retry "${DNF[@]}" makecache

echo "--- Removing Firefox from the base image ---"

if command -v flatpak >/dev/null 2>&1; then
  if flatpak list --system 2>/dev/null | grep -q org.mozilla.firefox; then
    flatpak uninstall --system -y org.mozilla.firefox || true
  fi
fi

if rpm -q firefox >/dev/null 2>&1; then
  "${DNF[@]}" remove --no-autoremove firefox || true
fi

echo "--- Installing NVIDIA supplementary packages ---"

install_available \
  libva-nvidia-driver nvidia-vaapi-driver nvidia-container-toolkit \
  vulkan-tools egl-utils glx-utils clinfo libva-utils mesa-vulkan-drivers \
  vulkan-loader vulkan-validation-layers nvidia-settings

echo "--- Installing browsers ---"

install_available \
  helium-bin brave-origin

echo "--- Installing gaming packages ---"

install_available \
  steam steam-devices mangohud

if rpm -q gamemode >/dev/null 2>&1; then
  echo "Removing GameMode (buggy on this image; uresourced supersedes it)"
  "${DNF[@]}" remove -y gamemode || true
fi

echo "--- Installing memory management tools ---"

install_available uresourced low-memory-monitor nohang prelockd

install -d -m 0755 /etc
cat >/etc/low-memory-monitor.conf <<'LMM'
[Configuration]
TriggerKernelOom = false
LMM

echo "--- Installing power management (tuned + tuned-ppd) ---"

install_available tuned tuned-ppd

install -d -m 0755 /etc/tuned
cat >/etc/tuned/ppd.conf <<'PPDCONF'
[main]
default=performance
battery_detection=true
sysfs_acpi_monitor=true

[profiles]
power-saver=powersave
balanced=balanced
performance=latency-performance

[battery]
balanced=balanced-battery
PPDCONF

echo "--- Installing desktop applications ---"

install_available \
  kitty umu-launcher yazi \
  code lact \
  gamescope \
  ananicy-cpp \
  faugus-launcher \
  tmux lollypop rhythmbox fragments qbittorrent

echo "--- Installing desktop integration ---"

install_available \
  mpv kdeconnectd libnotify systemd-ukify

echo "--- Installing developer utilities ---"

install_available \
  bat eza fd-find ripgrep fzf duf

echo "--- Installing chat clients ---"

install_available \
  nicotine+

echo "--- Installing CLI tools ---"

install_available \
  uv helix yt-dlp gh zoxide just trivy

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

echo "--- Installing sudo-rs ---"

install_available \
  sudo-rs

echo "--- Configuring wheel NOPASSWD sudoers drop-in ---"
install -d -m 0755 /etc/sudoers.d
SUDOERS_TMP="/tmp/99-vibes-wheel-nopasswd"
cat >"${SUDOERS_TMP}" <<'SUDOERS'
%wheel ALL=(ALL) NOPASSWD: ALL
SUDOERS
install -m 0440 -o root -g root "${SUDOERS_TMP}" \
  /etc/sudoers.d/99-vibes-wheel-nopasswd
rm -f "${SUDOERS_TMP}"

echo "--- Installing Yaru theme packs ---"

install_available \
  yaru-gtk3-theme yaru-gtk4-theme gnome-shell-theme-yaru yaru-icon-theme

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

echo "--- Installing fonts ---"

install_available \
  nerd-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  hack-fonts iosevka-fonts \
  ibm-plex-sans-fonts ibm-plex-serif-fonts adobe-source-serif-pro-fonts \
  adobe-source-code-pro-fonts adobe-source-sans-pro-fonts \
  liberation-fonts-all \
  google-noto-sans-arabic-fonts google-noto-naskh-arabic-fonts google-noto-kufi-arabic-fonts

echo "--- Installing language data ---"

install_available \
  hunspell hunspell-en-US hunspell-ar hyphen-en hyphen-ar \
  aspell aspell-en aspell-ar words autocorr-en autocorr-ar

echo "--- Installing audio packages ---"

install_available \
  wireplumber pipewire pipewire-utils pipewire-alsa \
  pipewire-pulseaudio pipewire-jack-audio-connection-kit

echo "--- Installing build tools and core utilities ---"

install_available \
  git make gcc clang llvm bpftool nodejs npm jq unzip rsync file which \
  libbpf libbpf-devel libcap libcap-devel libnl3 libnl3-devel \
  python3-docutils elfutils-libelf-devel pkgconf-pkg-config \
  zlib-devel ninja-build tar gzip xz

echo "--- Configuring browser policies ---"

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

echo "--- Configuring media players ---"

install -d -m 0755 /etc/mpv
cat >/etc/mpv/mpv.conf <<'MPVCONF'
hwdec=auto-safe
MPVCONF

echo "--- Configuring desktop environment variables ---"

install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/90-vibes-desktop-env.conf <<'EOFENV'
MOZ_ENABLE_WAYLAND=1
MOZ_WEBRENDER=1
LIBVA_DRIVER_NAME=nvidia
VDPAU_DRIVER=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
NVD_BACKEND=direct

VKD3D_CONFIG=descriptor_heap

QT_LOGGING_RULES=*.debug=false;*.info=false

XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
__GL_SHADER_DISK_CACHE_PATH=${XDG_CACHE_HOME}/nvidia/GLCache
MESA_SHADER_CACHE_DIR=${XDG_CACHE_HOME}/mesa_shader_cache
DXVK_STATE_CACHE_PATH=${XDG_CACHE_HOME}/dxvk-cache

QSG_DISK_CACHE=1

__GL_SHADER_DISK_CACHE=1
__GL_SHADER_DISK_CACHE_SIZE=107374182400
__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
EOFENV

echo "--- Configuring system services ---"

install -d -m 0755 /etc/systemd/system/multi-user.target.wants

if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
  ln -sf /usr/lib/systemd/system/lactd.service \
    /etc/systemd/system/multi-user.target.wants/lactd.service
fi

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

for unit in uresourced.service low-memory-monitor.service; do
  for candidate in "/usr/lib/systemd/system/${unit}" "/lib/systemd/system/${unit}"; do
    if [[ -f "$candidate" ]]; then
      ln -sf "$candidate" "/etc/systemd/system/multi-user.target.wants/${unit}"
      echo "${unit} service enabled"
      break
    fi
  done
done

install -d -m 0755 /etc/systemd/system
if [[ -e /usr/lib/systemd/system/systemd-oomd.service ]]; then
  ln -sf /dev/null /etc/systemd/system/systemd-oomd.service
  echo "systemd-oomd masked (nohang replaces it)"
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

for unit in tuned.service tuned-ppd.service; do
  for candidate in "/usr/lib/systemd/system/${unit}" "/lib/systemd/system/${unit}"; do
    if [[ -f "$candidate" ]]; then
      ln -sf "$candidate" "/etc/systemd/system/multi-user.target.wants/${unit}"
      echo "${unit} enabled"
      break
    fi
  done
done

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
ConditionPathIsReadWrite=/sys/fs/selinux
ExecStart=/usr/sbin/setsebool -P selinuxuser_execmod on

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/vibes-selinux.service \
  /etc/systemd/system/multi-user.target.wants/vibes-selinux.service
echo "vibes-selinux.service enabled"

echo "--- Controlling automatic updates ---"

install -d -m 0755 /etc/systemd/system
for unit in ublue-update.timer bootc-fetch-apply-updates.timer \
    flatpak-update.timer updates-stage.timer; do
  if [[ -e "/usr/lib/systemd/system/${unit}" || -e "/etc/systemd/system/${unit}" ]]; then
    ln -sf /dev/null "/etc/systemd/system/${unit}"
    echo "${unit} masked (manual updates)"
  fi
done

install -d -m 0755 /usr/lib/systemd/system
cat >/usr/lib/systemd/system/vibes-update-check.service <<'UNIT'
[Unit]
Description=Vibes weekly update check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/vibes-update-check.sh
UNIT

cat >/usr/lib/systemd/system/vibes-update-check.timer <<'TIMER'
[Unit]
Description=Weekly Vibes update notification

[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

install -d -m 0755 /etc/systemd/system/timers.target.wants
ln -sf /usr/lib/systemd/system/vibes-update-check.timer \
  /etc/systemd/system/timers.target.wants/vibes-update-check.timer
echo "vibes-update-check.timer enabled (weekly notification only)"

echo "--- Verifying firewall policy ---"

if [[ -f /usr/lib/firewalld/zones/FedoraWorkstation.xml ]] \
  && grep -q '1025-65535' /usr/lib/firewalld/zones/FedoraWorkstation.xml; then
  echo "OK: FedoraWorkstation zone opens 1025-65535 (Steam/KDE Connect/torrents/media pass)"
else
  echo "WARN: FedoraWorkstation zone with 1025-65535 not found; verify the firewall" >&2
  echo "      does not block Steam, KDE Connect, torrents or media servers" >&2
fi

echo "--- Cleaning up ---"
clean_build_artifacts

echo "=== Repositories and RPM packages configured successfully ==="
