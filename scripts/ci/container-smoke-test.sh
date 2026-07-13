#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:?IMAGE must be set, e.g. ghcr.io/owner/image:latest}"
MANIFEST_PATH="${MANIFEST_PATH:-$PWD/vibes-packages-manifest.txt}"
FAILURES=0

run_in_image() {
  local entrypoint="$1"
  shift
  podman run --rm --pull=never --entrypoint "$entrypoint" "$IMAGE" "$@"
}

path_exists() {
  local path="$1"
  run_in_image /usr/bin/stat "$path" >/dev/null 2>&1
}

require_path() {
  local path="$1"
  if path_exists "$path"; then
    echo "OK: ${path}"
  else
    echo "MISSING: ${path}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

warn_if_missing() {
  local path="$1"
  if path_exists "$path"; then
    echo "OK: ${path}"
  else
    echo "WARN: optional path missing: ${path}" >&2
  fi
}

require_any_path() {
  local found=1
  local path
  for path in "$@"; do
    if path_exists "$path"; then
      echo "OK: ${path}"
      found=0
      break
    fi
  done

  if (( found != 0 )); then
    echo "MISSING: none of the expected paths exist: $*" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

rpm_installed() {
  local package="$1"
  run_in_image /usr/bin/rpm -q "$package" >/dev/null 2>&1
}

require_rpm() {
  local package="$1"
  if rpm_installed "$package"; then
    echo "OK: ${package} RPM"
  else
    echo "MISSING: ${package} RPM" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

require_rpm_or_path() {
  local package="$1"
  local path="$2"
  if rpm_installed "$package"; then
    echo "OK: ${package} RPM"
  elif path_exists "$path"; then
    echo "OK: ${path}"
  else
    echo "MISSING: ${package} RPM or ${path}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

echo "Pulling image: ${IMAGE}"
podman pull --quiet "$IMAGE"

echo "=== bootc container lint ==="
podman run --rm --privileged --pull=never --entrypoint /usr/bin/bootc "$IMAGE" container lint

echo "=== Filesystem smoke checks ==="
require_path /usr/sbin/bpftune
require_path /usr/bin/code
require_path /usr/bin/gamescope
require_path /usr/bin/kitty
require_path /usr/bin/mangohud
require_path /usr/bin/opencode
require_path /usr/bin/scx_lavd
require_path /usr/bin/steam
require_path /usr/bin/umu-run
require_path /usr/bin/zed
require_path /usr/lib/vibes-apps/lmstudio/LM_Studio.AppImage
require_path /usr/lib64/ladspa/librnnoise_ladspa.so
require_path /etc/pipewire/pipewire.conf.d/99-input-denoising.conf
require_path /etc/profile.d/90-vibes-nvidia-accel.sh
require_path /etc/scx_loader/config.toml
require_path /etc/systemd/system/multi-user.target.wants/bpftune.service
require_path /etc/yum.repos.d/terra.repo
require_path /usr/share/color-schemes/Darkly.colors
require_path /usr/share/themes/Darkly
require_path /usr/share/vibes/themes-manifest.txt
require_path /usr/share/plasma/look-and-feel/Beauty-Color-Global-6
require_path /usr/share/plasma/look-and-feel/com.github.ddc.DDCmacOsTahoe-dark
require_path /usr/share/plasma/look-and-feel/com.github.vinceliuice.McMojave
require_path /usr/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur
require_path /usr/share/icons/DDCmacOsMonterey-cursor-white
require_path /usr/share/icons/DDCmacOsTahoe-cursor-dark
require_path /usr/share/icons/DDCmacOsTahoe-cursor-mixed
require_path /usr/share/icons/DDCmacOsTahoe-cursor-white
require_path /usr/share/icons/WhiteSur-cursors
require_any_path \
  /etc/systemd/system/multi-user.target.wants/scx_loader.service \
  /etc/systemd/system/multi-user.target.wants/scx-lavd.service
warn_if_missing /usr/bin/lact
warn_if_missing /usr/bin/pcmanfm-qt

require_rpm brave-origin
require_rpm firefox
require_rpm steam-devices
require_rpm_or_path darkly /usr/bin/darkly-settings6
require_rpm_or_path heroic /usr/bin/heroic
require_rpm_or_path lutris /usr/bin/lutris
require_rpm_or_path waterfox /usr/bin/waterfox
require_rpm_or_path WhiteSur-cursors /usr/share/icons/WhiteSur-cursors

echo "=== Extract package manifest ==="
run_in_image /usr/bin/rpm -qa --qf '%{NAME}\n' | sort > "$MANIFEST_PATH"

echo "Package manifest written to ${MANIFEST_PATH}"

if (( FAILURES != 0 )); then
  echo "ERROR: ${FAILURES} required smoke check(s) failed" >&2
  exit 1
fi

echo "Container smoke checks passed."
