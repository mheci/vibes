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
COREDUMP_LOG="$LOG_DIR/coredumps.log"
THEMES_LOG="$LOG_DIR/themes.log"

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
if grep -Eaiq "Kernel panic|not syncing|Oops:|BUG:|general protection fault|soft lockup|hard LOCKUP|RCU stall|watchdog: BUG|Call Trace:" "$DMESG_LOG"; then
  fail "Kernel panic/oops/lockup detected in dmesg"
else
  pass "No kernel panics or oopses in dmesg"
fi

# 2. Systemd health
systemctl --failed --no-pager > "$SYSTEMD_LOG" 2>/dev/null || true
failed_units="$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)"
if [[ -n "$failed_units" ]]; then
  for unit in $failed_units; do
    warn "systemd unit failed: $unit"
  done
else
  pass "No failed systemd units"
fi

# 3. Journal error scan
journalctl -p err --no-pager -n 1000 > "$JOURNAL_LOG" 2>/dev/null || true
journal_errors="$(grep -civ '^$' "$JOURNAL_LOG" || echo 0)"
if [[ "$journal_errors" -gt 20 ]]; then
  warn "High number of journal errors ($journal_errors)"
else
  pass "Journal error count acceptable ($journal_errors)"
fi

# 4. Coredumps
coredumpctl --no-pager --no-legend list > "$COREDUMP_LOG" 2>/dev/null || true
if grep -q . "$COREDUMP_LOG"; then
  fail "System reported one or more coredumps"
else
  pass "No coredumps recorded"
fi

# 5. Critical binaries
CRITICAL_BINS=(
  bpftune
  code
  darkly-settings6
  firefox
  gamescope
  heroic
  kitty
  lmstudio
  lutris
  mangohud
  opencode
  scx_lavd
  steam
  umu-run
  vicinae
  waterfox
  zed
)
for bin in "${CRITICAL_BINS[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "Binary present: $bin"
  else
    fail "Binary missing: $bin"
  fi
done

OPTIONAL_BINS=(faugus-launcher lact pcmanfm-qt)
for bin in "${OPTIONAL_BINS[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "Optional binary present: $bin"
  else
    warn "Optional binary missing: $bin"
  fi
done

# 6. Critical packages / repositories
REQUIRED_RPMS=(
  brave-origin
  darkly
  firefox
  steam-devices
  terra-release
  waterfox
)
for pkg in "${REQUIRED_RPMS[@]}"; do
  if rpm -q "$pkg" >/dev/null 2>&1; then
    pass "RPM installed: $pkg"
  else
    fail "RPM missing: $pkg"
  fi
done

if [[ -f /etc/yum.repos.d/terra.repo ]]; then
  pass "Terra repo file present"
else
  fail "Terra repo file missing"
fi

# 7. Critical services enabled
if systemctl is-enabled bpftune.service >/dev/null 2>&1; then
  pass "Service enabled: bpftune.service"
else
  fail "Service not enabled: bpftune.service"
fi

if systemctl is-enabled scx_loader.service >/dev/null 2>&1 || systemctl is-enabled scx-lavd.service >/dev/null 2>&1; then
  pass "sched_ext service enabled"
else
  fail "No sched_ext service enabled"
fi

if systemctl is-enabled lactd.service >/dev/null 2>&1; then
  pass "Service enabled: lactd.service"
else
  warn "Service not enabled: lactd.service"
fi

# 8. NVIDIA / GPU acceleration
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
  warn "NVIDIA kernel modules not loaded (expected on CI without GPU passthrough)"
fi

if [[ -f /etc/profile.d/90-vibes-nvidia-accel.sh ]]; then
  pass "NVIDIA acceleration profile script present"
else
  fail "NVIDIA acceleration profile script missing"
fi

# 9. Audio stack
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

# 10. Codecs / thumbnails
rpm -qa | grep -E 'ffmpeg|gstreamer|thumbnail|tumbler|lame|x264|x265' | sort > "$PKG_LOG" || true
if grep -q ffmpeg "$PKG_LOG"; then
  pass "FFmpeg packages installed"
else
  fail "FFmpeg packages not found"
fi

# 11. Fonts
if fc-list | grep -Eqi 'Inter|JetBrains Mono|Fira Code|Cascadia|Noto Sans Arabic|Noto Naskh Arabic'; then
  pass "Requested fonts detected"
else
  fail "Requested fonts not detected"
fi

# 12. Spellcheck dictionaries
for dict in en_US ar; do
  if find /usr/share/hunspell -name "${dict}*" -print -quit 2>/dev/null | grep -q .; then
    pass "Hunspell dictionary present: $dict"
  else
    fail "Hunspell dictionary missing: $dict"
  fi
done

# 13. Theme assets
{
  for path in \
    /usr/share/themes/Darkly \
    /usr/share/plasma/look-and-feel/Beauty-Color-Global-6 \
    /usr/share/plasma/look-and-feel/com.github.ddc.DDCmacOsTahoe-dark \
    /usr/share/plasma/look-and-feel/com.github.vinceliuice.McMojave \
    /usr/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur \
    /usr/share/icons/DDCmacOsMonterey-cursor-white \
    /usr/share/icons/DDCmacOsTahoe-cursor-dark \
    /usr/share/icons/DDCmacOsTahoe-cursor-mixed \
    /usr/share/icons/DDCmacOsTahoe-cursor-white \
    /usr/share/icons/WhiteSur-cursors \
    /usr/share/vibes/themes-manifest.txt; do
    if [[ -e "$path" ]]; then
      echo "OK: $path"
    else
      echo "MISSING: $path"
    fi
  done
} > "$THEMES_LOG"

while IFS= read -r line; do
  if [[ "$line" == OK:* ]]; then
    pass "$line"
  elif [[ "$line" == MISSING:* ]]; then
    fail "$line"
  fi
done < "$THEMES_LOG"

# 14. scx_loader config
if [[ -f /etc/scx_loader/config.toml ]]; then
  pass "scx_loader config present"
  if grep -q -- '--performance' /etc/scx_loader/config.toml; then
    pass "scx_loader LAVD performance mode configured"
  else
    fail "scx_loader LAVD performance mode not configured"
  fi
else
  fail "scx_loader config missing"
fi

# 15. bootc / rpm-ostree sanity
if command -v bootc >/dev/null 2>&1; then
  pass "bootc CLI present"
  if bootc status >/dev/null 2>&1; then
    pass "bootc status works"
  else
    warn "bootc status returned error"
  fi
else
  fail "bootc CLI missing"
fi

if command -v rpm-ostree >/dev/null 2>&1; then
  if rpm-ostree status >/dev/null 2>&1; then
    pass "rpm-ostree status works"
  else
    fail "rpm-ostree status returned error"
  fi
else
  fail "rpm-ostree missing"
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
