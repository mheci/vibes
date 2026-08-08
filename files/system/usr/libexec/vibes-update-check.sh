#!/usr/bin/env bash
set -euo pipefail

UPDATES=""
if output="$(bootc upgrade --check 2>/dev/null)"; then
  if [[ -n "${output}" ]]; then
    UPDATES="OS update: ${output}"
  fi
fi

if [[ -z "${UPDATES}" ]]; then
  exit 0
fi

session_user="$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n1)"
if [[ -z "${session_user}" ]]; then
  exit 0
fi

uid="$(id -u "${session_user}")"
sudo -u "${session_user}" \
  env XDG_RUNTIME_DIR="/run/user/${uid}" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
      DISPLAY="${DISPLAY:-:0}" \
  notify-send -u normal -i system-software-update \
    "Vibes update available" \
    "An OS update is ready. Apply it with: sudo bootc upgrade"
