#!/usr/bin/env bash
# Install desktop themes, cursor packs, and visual assets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Installing Desktop Themes ==="

# Create required directory structure
mkdir -p \
  /usr/share/themes \
  /usr/share/icons

# ---------------------------------------------------------------------------
# macOS cursor themes
# Pinned to v2.0.0 (2024-09-15); update deliberately after testing.
# ---------------------------------------------------------------------------
echo "Installing macOS cursor themes..."
CURSOR_TAG="v2.0.0"
CURSOR_BASE="https://github.com/ful1e5/apple_cursor/releases/download/${CURSOR_TAG}"

for theme in macOS-BigSur macOS-Monterey; do
  echo "  Downloading ${theme}..."
  if retry 3 5 curl -fL -o "/tmp/${theme}.tar.gz" "${CURSOR_BASE}/${theme}.tar.gz"; then
    tar -xzf "/tmp/${theme}.tar.gz" -C /usr/share/icons/ || true
    rm -f "/tmp/${theme}.tar.gz"
  else
    echo "  WARN: failed to download ${theme} cursor theme" >&2
  fi
done

# ---------------------------------------------------------------------------
# MoreWaita icon theme (Adwaita companion with icons for third-party apps)
# Pinned commit; the theme files live at the repository root, and the
# upstream install.sh copies them system-wide and rebuilds the icon cache.
# ---------------------------------------------------------------------------
echo "Installing MoreWaita icon theme..."
MOREWAITA_PIN="53bc2ba9c2cdc1f26ef822fcdd8a95e01cce5d58"
rm -rf /tmp/morewaita
install -d -m 0755 /tmp/morewaita
git -C /tmp/morewaita init -q
git -C /tmp/morewaita remote add origin https://github.com/somepaulo/MoreWaita.git
retry git -C /tmp/morewaita fetch -q --depth 1 origin "${MOREWAITA_PIN}"
git -C /tmp/morewaita checkout -q FETCH_HEAD
bash /tmp/morewaita/install.sh
rm -rf /tmp/morewaita

echo "=== Desktop themes installed successfully ==="
