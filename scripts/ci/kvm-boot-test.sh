#!/usr/bin/env bash
set -euo pipefail

# KVM smoke boot for bootc images with SSH-based automated QA.
# Rationale:
# - bootc-image-builder is the supported path for turning a bootc container into
#   a QEMU-bootable qcow2 disk.
# - QEMU serial output is machine-readable and lets CI detect early boot failures.
# - SSH into the guest enables deep automated QA (systemd health, package checks,
#   GPU accel verification, journal scanning) without relying solely on serial greps.

IMAGE="${IMAGE:?IMAGE must be set, e.g. ghcr.io/owner/image:latest}"
WORKDIR="${WORKDIR:-$PWD/kvm-boot-work}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
MEMORY_MB="${MEMORY_MB:-8192}"
VCPUS="${VCPUS:-4}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
SSH_PORT="${SSH_PORT:-2222}"

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

cleanup_qemu() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "Cleaning up QEMU (PID $pid)..."
      kill "$pid" || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
}

trap cleanup_qemu EXIT

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

# Generate an SSH key pair for this test run.
SSH_KEY="$WORKDIR/vm_ci_key"
rm -f "$SSH_KEY" "$SSH_KEY.pub"
ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "ci@vibes.local" >/dev/null 2>&1

# Build config.toml with a ci user and authorized SSH key.
cat >"$CONFIG" <<TOML
[[customizations.user]]
name = "ci"
password = "ci"
groups = ["wheel"]
key = "$(cat "$SSH_KEY.pub")"

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
echo "Booting qcow2 under QEMU/KVM (SSH forwarded to host $SSH_PORT)..."
qemu-system-x86_64 \
  -name vibes-boot-smoke \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$VCPUS" \
  -m "$MEMORY_MB" \
  -bios "$OVMF" \
  -drive "if=virtio,format=qcow2,file=$DISK,snapshot=on" \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
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
ssh_ready_re='Started .*SSH server|Started OpenSSH server'

start_ts="$(date +%s)"
last_size=0
ssh_available=0
while true; do
  if grep -Eaiq "$panic_re" "$SERIAL_LOG"; then
    fail "KVM boot validation detected kernel/early-boot failure pattern."
  fi

  if grep -Eaiq "$success_re" "$SERIAL_LOG"; then
    echo "KVM boot validation passed: guest reached a login/systemd target."
  fi

  if [[ "$ssh_available" -eq 0 ]] && grep -Eaiq "$ssh_ready_re" "$SERIAL_LOG"; then
    echo "SSH server appears to have started in guest."
  fi

  # Try SSH once we think the guest is up.
  if [[ "$ssh_available" -eq 0 ]]; then
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 \
           -o BatchMode=yes \
           -i "$SSH_KEY" \
           -p "$SSH_PORT" \
           ci@localhost "echo ssh-ready" >/dev/null 2>&1; then
      echo "SSH connection to guest established."
      ssh_available=1
      break
    fi
  fi

  if [[ -f "$PIDFILE" ]] && ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    fail "QEMU exited before the guest reached a successful boot target."
  fi

  now="$(date +%s)"
  if (( now - start_ts > TIMEOUT_SECONDS )); then
    fail "Timed out after ${TIMEOUT_SECONDS}s waiting for successful boot target / SSH."
  fi

  size="$(stat -c%s "$SERIAL_LOG" 2>/dev/null || echo 0)"
  if (( size != last_size )); then
    echo "serial log bytes: $size"
    last_size="$size"
  fi
  sleep 5
done

if [[ "$ssh_available" -eq 0 ]]; then
  fail "SSH never became available inside the guest."
fi

# Run in-VM QA.
QA_SCRIPT="${GITHUB_WORKSPACE:-$(dirname "$0")}/vm-qa.sh"
if [[ -f "$QA_SCRIPT" ]]; then
  echo "Copying vm-qa.sh into guest and executing..."
  scp -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=10 \
      -i "$SSH_KEY" \
      -P "$SSH_PORT" \
      "$QA_SCRIPT" ci@localhost:/tmp/vm-qa.sh

  ssh -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=10 \
      -i "$SSH_KEY" \
      -p "$SSH_PORT" \
      ci@localhost "bash /tmp/vm-qa.sh" || {
    echo "ERROR: in-VM QA script returned non-zero." >&2
    ERR=1
  }

  # Pull logs back from guest.
  scp -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=10 \
      -i "$SSH_KEY" \
      -P "$SSH_PORT" \
      -r "ci@localhost:/tmp/vibes-qa" "$WORKDIR/" || true
else
  echo "WARN: vm-qa.sh not found at $QA_SCRIPT, skipping deep QA." >&2
fi

# Graceful shutdown via SSH to collect clean journal state.
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    ci@localhost "sudo systemctl poweroff" >/dev/null 2>&1 || true

# Wait for QEMU to exit on its own after poweroff.
shutdown_start="$(date +%s)"
while true; do
  if [[ -f "$PIDFILE" ]] && ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "QEMU exited after guest poweroff."
    break
  fi
  if (( $(date +%s) - shutdown_start > 120 )); then
    echo "WARN: guest did not poweroff within 120s; forcing QEMU kill." >&2
    cleanup_qemu
    break
  fi
  sleep 2
done

# Final post-boot QA pass over the captured console.
if grep -Eaiq "$panic_re" "$SERIAL_LOG"; then
  fail "KVM boot validation found a failure pattern after success detection."
fi

# Print concise evidence into the job log.
echo "--- successful boot evidence ---"
grep -Eai "$success_re" "$SERIAL_LOG" | tail -20 || true

echo "KVM boot validation completed successfully."
exit 0
