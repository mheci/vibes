#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Desktop Themes ==="

# Create required directory structure
mkdir -p \
  /usr/share/themes \
  /usr/share/icons \
  /usr/share/color-schemes \
  /usr/share/plasma/desktoptheme \
  /usr/share/plasma/look-and-feel

retry() {
  local attempts=3 delay=5 n=1
  until "$@"; do
    if (( n >= attempts )); then
      echo "ERROR: command failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    echo "WARN: retrying in ${delay}s: $*" >&2
    sleep "$delay"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

# --- Darkly (Plasma window decoration + color scheme) ---
echo "Installing Darkly theme..."
retry git clone --depth 1 https://github.com/Bali10050/Darkly /tmp/darkly

if [[ -d /tmp/darkly/color-schemes ]]; then
  cp -a /tmp/darkly/color-schemes/. /usr/share/color-schemes/
fi
if [[ -d /tmp/darkly/plasma/desktoptheme ]]; then
  cp -a /tmp/darkly/plasma/desktoptheme/. /usr/share/plasma/desktoptheme/
fi
if [[ -d /tmp/darkly/plasma/look-and-feel ]]; then
  cp -a /tmp/darkly/plasma/look-and-feel/. /usr/share/plasma/look-and-feel/
fi
rm -rf /tmp/darkly
echo "Darkly theme installed."

# --- Beauty-Plasma-Themes ---
echo "Installing Beauty-Plasma-Themes..."
retry git clone --depth 1 https://github.com/L4ki/Beauty-Plasma-Themes /tmp/beauty

# Copy theme directories individually to preserve structure
for dir in /tmp/beauty/*/; do
  dirname="$(basename "$dir")"
  if [[ -d "$dir/plasma" ]]; then
    # This is a theme directory with plasma subfolder
    cp -a "$dir" "/usr/share/plasma/desktoptheme/${dirname}" 2>/dev/null || true
  fi
done

# Also copy any top-level plasma/desktoptheme entries
if [[ -d /tmp/beauty/plasma/desktoptheme ]]; then
  cp -a /tmp/beauty/plasma/desktoptheme/. /usr/share/plasma/desktoptheme/ 2>/dev/null || true
fi
rm -rf /tmp/beauty
echo "Beauty-Plasma-Themes installed."

# --- macOS cursor themes ---
echo "Installing macOS cursor themes..."
CURSOR_BASE="https://github.com/ful1e5/apple_cursor/releases/download/v2.0.0"

for theme in macOS-BigSur macOS-Monterey; do
  echo "  Downloading ${theme}..."
  retry curl -fL -o "/tmp/${theme}.tar.gz" "${CURSOR_BASE}/${theme}.tar.gz"
  tar -xzf "/tmp/${theme}.tar.gz" -C /usr/share/icons/
  rm -f "/tmp/${theme}.tar.gz"
done

echo "=== Desktop themes installed successfully ==="
