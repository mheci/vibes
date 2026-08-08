#!/usr/bin/env bash
# Post-files-module verification: the files module copies files/system/**
# into the image after all script modules, so artifacts created there
# (configs, service binaries, the justfile suite) can only be validated
# by a script that runs after it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Verifying files-module output ==="

errors=0

for f in /etc/containers/policy.json \
    /etc/pki/containers/vibes-cosign.pub \
    /etc/xdg/kwinrc /etc/xdg/kdeglobals /etc/xdg/powerdevilrc \
    /etc/fonts/local.conf \
    /usr/share/vibes/justfile \
    /usr/share/vibes/kernel-version \
    /usr/lib/systemd/system/vibes-update-check.service \
    /usr/lib/systemd/system/vibes-update-check.timer \
    /usr/lib/systemd/system/greenboot-task-runner.service; do
  check_file "$f"
done

if [[ -f /etc/systemd/system/multi-user.target.wants/greenboot-health-check.service ]]; then
  echo "  OK: greenboot-health-check.service enabled"
else
  echo "  FAIL: greenboot-health-check.service not enabled" >&2
  errors=$((errors + 1))
fi

for script in /usr/libexec/vibes-update-check.sh \
    /usr/lib/greenboot/check/warning.d/40-systemd-failed.sh \
    /usr/libexec/vibes-luks-tpm-encrypt.sh \
    /usr/libexec/vibes-dns-encrypted.sh; do
  if [[ -x "$script" ]]; then
    echo "  OK: $script (executable)"
  else
    echo "  FAIL: $script missing or not executable" >&2
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} files-module verification check(s) failed" >&2
  exit 1
fi

echo "=== Files-module output verified successfully ==="
