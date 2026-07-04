#!/usr/bin/env bash
set -euo pipefail

# KVM smoke boot for bootc images.
# Rationale:
# - bootc-image-builder is the supported path for turning a bootc container into
#   a QEMU-bootable qcow2 disk.
# - QEMU serial output is machine-readable and lets CI detect early boot failures
#   such as kernel panics, oopses, dracut failures, and emergency mode.
# - This is intentionally a smoke boot, not a full openQA-style desktop test.

IMAGE="${IMAGE:?IMAGE must be set, e.g. ghcr.io/owner/image:latest}"
WORKDIR="${WORKDIR:-$PWD/kvm-boot-work}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
MEMORY_MB="${MEMORY_MB:-8192}"
VCPUS="${VCPUS:-4}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"

mkdir -p "$WORKDIR" "$WORKDIR/output"
SERIAL_LOG="$WORKDIR/serial-console.log"
BIB_LOG="$WORKDIR/bootc-image-builder.log"
QEMU_LOG="$WORKDIR/qemu.log"
CONFIG="$WORKDIR/config.toml"
PIDFILE="$WORKDIR/qemu.pid"
: >"$SERIAL_LOG"
: >"$QEMU_LOG"

fail() {
  echo "ERROR: $*" >&2
  echo "--- serial console tail ---" >&2
  tail -250 "$SERIAL_LOG" >&2 || true
  exit 1
}

if [[ ! -e /dev/kvm ]]; then
  fail "/dev/kvm is not available. KVM boot validation requires a runner with nested virtualization."
fi

# Best-effort make KVM accessible on GitHub-hosted runners.
sudo chmod 666 /dev/kvm || true

# Prefer 4M OVMF when available, fall back to distro default.
OVMF=""
for candidate in \
  /usr/share/OVMF/OVMF_CODE_4M.fd \
  /usr/share/OVMF/OVMF_CODE.fd \
  /usr/share/qemu/OVMF.fd; do
  if [[ -r "$candidate" ]]; then
    OVMF="$candidate"
    break
  fi
done
[[ -n "$OVMF" ]] || fail "No readable OVMF firmware found; install ovmf."

cat >"$CONFIG" <<'TOML'
[[customizations.user]]
name = "ci"
password = "ci"
groups = ["wheel"]

[customizations.kernel]
append = "console=ttyS0,115200n8 console=tty0 systemd.log_target=console systemd.journald.forward_to_console=1 rd.shell=0 oops=panic panic=30 softlockup_panic=1 hung_task_panic=1 nmi_watchdog=panic"
TOML

echo "Pulling image for boot conversion: $IMAGE"
sudo podman pull "$IMAGE"

# Build qcow2. Mount root's container storage because sudo podman pulled there.
echo "Building qcow2 with bootc-image-builder..."
set -o pipefail
sudo podman run \
  --rm \
  --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$CONFIG:/config.toml:ro" \
  -v "$WORKDIR/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BIB_IMAGE" \
  --type qcow2 \
  --use-librepo=True \
  "$IMAGE" 2>&1 | tee "$BIB_LOG"

DISK="$(find "$WORKDIR/output" -type f \( -name '*.qcow2' -o -name 'disk.qcow2' \) | head -n1)"
[[ -n "$DISK" && -s "$DISK" ]] || fail "bootc-image-builder did not produce a qcow2 disk."
qemu-img info "$DISK"

# Boot read-only/snapshot so validation never mutates the produced artifact.
echo "Booting qcow2 under QEMU/KVM..."
qemu-system-x86_64 \
  -name vibes-boot-smoke \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$VCPUS" \
  -m "$MEMORY_MB" \
  -bios "$OVMF" \
  -drive "if=virtio,format=qcow2,file=$DISK,snapshot=on" \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -serial "file:$SERIAL_LOG" \
  -display none \
  -no-reboot \
  -watchdog i6300esb \
  -watchdog-action poweroff \
  -pidfile "$PIDFILE" \
  -daemonize 2>"$QEMU_LOG"

panic_re='Kernel panic|not syncing|Oops:|BUG:|general protection fault|Unable to mount root fs|Cannot open root device|dracut.*(timeout|Warning:)|Entering emergency mode|You are in emergency mode|Dependency failed for .*File System|Failed to start .*Switch Root|watchdog: BUG|soft lockup|hard LOCKUP|RCU stall'
success_re='Reached target .*Multi-User|Reached target .*Graphical|Started .*Getty|login:'

start_ts="$(date +%s)"
last_size=0
while true; do
  if grep -Eaiq "$panic_re" "$SERIAL_LOG"; then
    fail "KVM boot validation detected kernel/early-boot failure pattern."
  fi

  if grep -Eaiq "$success_re" "$SERIAL_LOG"; then
    echo "KVM boot validation passed: guest reached a login/systemd target."
    break
  fi

  if [[ -f "$PIDFILE" ]] && ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    fail "QEMU exited before the guest reached a successful boot target."
  fi

  now="$(date +%s)"
  if (( now - start_ts > TIMEOUT_SECONDS )); then
    fail "Timed out after ${TIMEOUT_SECONDS}s waiting for successful boot target."
  fi

  size="$(stat -c%s "$SERIAL_LOG" 2>/dev/null || echo 0)"
  if (( size != last_size )); then
    echo "serial log bytes: $size"
    last_size="$size"
  fi
  sleep 5
done

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" || true
  sleep 2
  kill -9 "$(cat "$PIDFILE")" 2>/dev/null || true
fi

# Final post-boot QA pass over the captured console.
if grep -Eaiq "$panic_re" "$SERIAL_LOG"; then
  fail "KVM boot validation found a failure pattern after success detection."
fi

# Print concise evidence into the job log.
echo "--- successful boot evidence ---"
grep -Eai "$success_re" "$SERIAL_LOG" | tail -20 || true
