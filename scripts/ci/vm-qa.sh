#!/usr/bin/env bash
set -euo pipefail

# In-VM QA script for Vibes image validation.
# This runs inside the booted KVM guest via SSH.

LOG_DIR="/tmp/vibes-qa"
mkdir -p "$LOG_DIR"
DMESG_LOG="$LOG_DIR/dmesg.log"
JOURNAL_LOG="$LOG_DIR/journal-errors.log"
SYSTEMD_LOG="$LOG_DIR/systemd-status.log"
PKG_LOG="$LOG_DIR/packages.log"
GPU_LOG="$LOG_DIR/gpu.log"
AUDIO_LOG="$LOG_DIR/audio.log"

ERRORS=0
WARNINGS=0

fail() {
  echo "FAIL: $*" >&2
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo "WARN: $*" >&2
  WARNINGS=$((WARNINGS + 1))
}

pass() {
  echo "PASS: $*"
}

# 1. Kernel / dmesg checks
dmesg > "$DMESG_LOG" 2>/dev/null || journalctl -k > "$DMESG_LOG" 2>/dev/null || true

if grep -Eaiq "Kernel panic|not syncing|Oops:|BUG:|general protection fault|soft lockup|hard LOCKUP|RCU stall|watchdog: BUG" "$DMESG_LOG"; then
  fail "Kernel panic/oops/lockup detected in dmesg"
else
  pass "No kernel panics or oopses in dmesg"
fi

# 2. Systemd health
systemctl --failed --no-pager > "$SYSTEMD_LOG" 2>/dev/null || true
failed_units="$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)"
if [[ -n "$failed_units" ]]; then
  for u in $failed_units; do
    warn "systemd unit failed: $u"
  done
else
  pass "No failed systemd units"
fi

# 3. Journal error scan (last 1000 lines, priority err and above)
journalctl -p err --no-pager -n 1000 > "$JOURNAL_LOG" 2>/dev/null || true
journal_errors="$(grep -civ '^$' "$JOURNAL_LOG" || echo 0)"
if [[ "$journal_errors" -gt 20 ]]; then
  warn "High number of journal errors ($journal_errors)"
else
  pass "Journal error count acceptable ($journal_errors)"
fi

# 4. Critical binaries
CRITICAL_BINS=(
  kitty firefox brave-origin
  code zed opencode lmstudio vicinae
  umu-launcher faugus-launcher
  heroic heroic-games-launcher
  scx_lavd bpftune
)
for bin in "${CRITICAL_BINS[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "Binary present: $bin"
  else
    warn "Binary missing: $bin"
  fi
done

# Optional binaries (may be excluded by Bazzite base image)
OPTIONAL_BINS=(pcmanfm-qt lact)
for bin in "${OPTIONAL_BINS[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "Optional binary present: $bin"
  else
    warn "Optional binary missing: $bin (excluded by base image)"
  fi
done

# 5. Critical services enabled
CRITICAL_SERVICES=(
  bpftune.service
  lactd.service
  scx_loader.service
  scx-lavd.service
)
for svc in "${CRITICAL_SERVICES[@]}"; do
  if systemctl is-enabled "$svc" >/dev/null 2>&1; then
    pass "Service enabled: $svc"
  else
    warn "Service not enabled: $svc"
  fi
done

# 6. NVIDIA / GPU acceleration
{
  echo "=== lsmod | grep nvidia ==="
  lsmod | grep nvidia || true
  echo "=== vainfo ==="
  vainfo 2>/dev/null || true
  echo "=== vulkaninfo --summary ==="
  vulkaninfo --summary 2>/dev/null || true
  echo "=== glxinfo -B ==="
  glxinfo -B 2>/dev/null || true
  echo "=== nvidia-smi ==="
  nvidia-smi 2>/dev/null || true
} > "$GPU_LOG"

if lsmod | grep -q nvidia; then
  pass "NVIDIA kernel modules loaded"
else
  warn "NVIDIA kernel modules not loaded (may be expected in CI without GPU passthrough)"
fi

if [[ -f /etc/profile.d/90-vibes-desktop-env.sh ]]; then
  pass "Desktop acceleration profile script present"
else
  fail "Desktop acceleration profile script missing"
fi

# 7. Audio stack
{
  echo "=== pipewire version ==="
  pipewire --version 2>/dev/null || true
  echo "=== wireplumber version ==="
  wireplumber --version 2>/dev/null || true
  echo "=== RNNoise plugin ==="
  ls -la /usr/lib64/ladspa/librnnoise_ladspa.so 2>/dev/null || true
} > "$AUDIO_LOG"

if [[ -f /usr/lib64/ladspa/librnnoise_ladspa.so ]]; then
  pass "RNNoise LADSPA plugin present"
else
  fail "RNNoise LADSPA plugin missing"
fi

if systemctl is-active --quiet pipewire.service 2>/dev/null || systemctl is-active --quiet pipewire.socket 2>/dev/null; then
  pass "PipeWire active"
else
  warn "PipeWire not active"
fi

# 8. Codecs / thumbnails
rpm -qa | grep -E 'ffmpeg|gstreamer|thumbnail|tumbler|lame|x264|x265' | sort > "$PKG_LOG" || true
if grep -q ffmpeg "$PKG_LOG"; then
  pass "FFmpeg packages installed"
else
  warn "FFmpeg packages not found"
fi

# 9. Fonts
if fc-list | grep -qi "nerd\|jetbrains\|fira code\|cascadia"; then
  pass "Nerd/developer fonts detected"
else
  warn "Nerd/developer fonts not detected"
fi

# 10. Spellcheck dictionaries
for dict in en_US ar; do
  if find /usr/share/hunspell -name "${dict}*" -print -quit 2>/dev/null | grep -q .; then
    pass "Hunspell dictionary present: $dict"
  else
    warn "Hunspell dictionary missing: $dict"
  fi
done

# 11. scx_loader config
if [[ -f /etc/scx_loader/config.toml ]]; then
  pass "scx_loader config present"
  if grep -q "\-\-performance" /etc/scx_loader/config.toml; then
    pass "scx_loader LAVD performance mode configured"
  else
    warn "scx_loader LAVD performance mode not configured"
  fi
else
  warn "scx_loader config missing"
fi

# 12. bootc sanity
if command -v bootc >/dev/null 2>&1; then
  pass "bootc CLI present"
  if bootc status >/dev/null 2>&1; then
    pass "bootc status works"
  else
    warn "bootc status returned error"
  fi
else
  warn "bootc CLI missing"
fi

# Summary
echo "========================================"
echo "VIBES VM QA SUMMARY"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo "========================================"

if [[ $ERRORS -gt 0 ]]; then
  exit 1
fi
exit 0
