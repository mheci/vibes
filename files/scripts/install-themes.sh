#!/usr/bin/env bash
set -euo pipefail

echo "Installing Themes..."

mkdir -p /usr/share/themes /usr/share/icons /usr/share/fonts /usr/share/color-schemes /usr/share/plasma/desktoptheme /usr/share/plasma/look-and-feel

# Install Darkly
git clone --depth 1 https://github.com/Bali10050/Darkly /tmp/darkly
if [ -d /tmp/darkly ]; then
    cp -r /tmp/darkly/color-schemes/* /usr/share/color-schemes/ 2>/dev/null || true
    cp -r /tmp/darkly/plasma/desktoptheme/* /usr/share/plasma/desktoptheme/ 2>/dev/null || true
    cp -r /tmp/darkly/plasma/look-and-feel/* /usr/share/plasma/look-and-feel/ 2>/dev/null || true
    rm -rf /tmp/darkly
fi

# Install Beauty-Plasma-Themes
git clone --depth 1 https://github.com/L4ki/Beauty-Plasma-Themes /tmp/beauty
if [ -d /tmp/beauty ]; then
    mkdir -p /usr/share/plasma/desktoptheme/Beauty-Plasma-Themes
    cp -r /tmp/beauty/* /usr/share/plasma/desktoptheme/Beauty-Plasma-Themes/ 2>/dev/null || true
    rm -rf /tmp/beauty
fi

# Install macOS cursor themes from binary release
curl -L -o /tmp/macOS-BigSur.tar.gz https://github.com/ful1e5/apple_cursor/releases/download/v2.0.0/macOS-BigSur.tar.gz
tar -xzf /tmp/macOS-BigSur.tar.gz -C /usr/share/icons/
rm -f /tmp/macOS-BigSur.tar.gz

curl -L -o /tmp/macOS-Monterey.tar.gz https://github.com/ful1e5/apple_cursor/releases/download/v2.0.0/macOS-Monterey.tar.gz
tar -xzf /tmp/macOS-Monterey.tar.gz -C /usr/share/icons/
rm -f /tmp/macOS-Monterey.tar.gz

