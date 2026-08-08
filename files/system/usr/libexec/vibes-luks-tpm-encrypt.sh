#!/usr/bin/env bash
# vjust luks-tpm-encrypt helper: format a block device with LUKS2 and
# enroll the TPM 2.0 for automatic unlock at boot.
set -euo pipefail

DEV="${1:-}"
if [[ -z "${DEV}" ]]; then
  echo "ERROR: usage: luks-tpm-encrypt <device>" >&2
  exit 1
fi
if [[ ! -b "${DEV}" ]]; then
  echo "ERROR: ${DEV} is not a block device" >&2
  exit 1
fi
if cryptsetup isLuks "${DEV}" 2>/dev/null; then
  echo "ERROR: ${DEV} is already a LUKS device" >&2
  exit 1
fi
if ! tpm2_getcap handles-pcr >/dev/null 2>&1; then
  echo "ERROR: no TPM 2.0 found; cannot set up automatic unlock" >&2
  exit 1
fi

echo "WARNING: all data on ${DEV} will be destroyed."
read -r -p "Type 'yes' to wipe and encrypt ${DEV} with LUKS2: " CONFIRM < /dev/tty
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted"
  exit 1
fi

echo "Formatting ${DEV} with LUKS2..."
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 "${DEV}"
echo "Enrolling the TPM 2.0 for automatic unlock (PCR 0+7)..."
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "${DEV}"

UUID="$(cryptsetup luksUUID "${DEV}")"
NAME="vault-${UUID:0:8}"
if ! grep -q "^${NAME} " /etc/crypttab 2>/dev/null; then
  echo "${NAME} UUID=${UUID} none tpm2-device=auto" >> /etc/crypttab
  systemctl daemon-reload
fi
echo "Added /etc/crypttab entry: ${NAME}"

# No dracut step: on bootc images the initramfs lives under a read-only
# /usr and is regenerated automatically at the next deployment; the
# generator picks the crypttab entry up from there.
echo "Done. ${DEV} will unlock automatically at boot via the TPM."
echo "The passphrase set during the format step still works as a fallback."
echo "Verify with: sudo vjust luks-status"
