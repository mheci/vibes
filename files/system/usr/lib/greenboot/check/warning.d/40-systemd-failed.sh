#!/usr/bin/env bash
# Warning-level greenboot check: report failed systemd units without
# triggering the automatic rollback. Units that commonly fail once at
# boot on this image are allowlisted so they do not produce noise.
set -euo pipefail

readarray -t failed < <(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}')
if [[ ${#failed[@]} -eq 0 ]]; then
  exit 0
fi

ALLOWLIST=(
  systemd-vconsole-setup.service
  systemd-boot-system-token.service
)
noise=0
for unit in "${failed[@]}"; do
  allowed=0
  for pattern in "${ALLOWLIST[@]}"; do
    if [[ "${unit}" == "${pattern}" ]]; then
      allowed=1
      break
    fi
  done
  if [[ ${allowed} -eq 0 ]]; then
    echo "failed unit: ${unit}" >&2
    noise=1
  fi
done

if [[ ${noise} -eq 1 ]]; then
  echo "greenboot: one or more systemd units are in a failed state" >&2
fi
exit 0
