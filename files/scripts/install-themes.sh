#!/usr/bin/env bash
set -euo pipefail

echo "Installing Themes..."

mkdir -p /usr/share/themes /usr/share/icons /usr/share/fonts /usr/share/color-schemes /usr/share/plasma/desktoptheme /usr/share/plasma/look-and-feel

# Install Darkly
if git clone --depth 1 https://github.com/Bali10050/Darkly /tmp/darkly; then
    cp -r /tmp/darkly/color-schemes/* /usr/share/color-schemes/ 2>/dev/null || echo "WARN: failed to copy Darkly color schemes"
    cp -r /tmp/darkly/plasma/desktoptheme/* /usr/share/plasma/desktoptheme/ 2>/dev/null || echo "WARN: failed to copy Darkly desktop theme"
    cp -r /tmp/darkly/plasma/look-and-feel/* /usr/share/plasma/look-and-feel/ 2>/dev/null || echo "WARN: failed to copy Darkly look and feel"
    rm -rf /tmp/darkly
else
    echo "WARN: Failed to clone Darkly theme"
fi

# Install Beauty-Plasma-Themes
if git clone --depth 1 https://github.com/L4ki/Beauty-Plasma-Themes /tmp/beauty; then
    mkdir -p /usr/share/plasma/desktoptheme/Beauty-Plasma-Themes
    cp -r /tmp/beauty/* /usr/share/plasma/desktoptheme/Beauty-Plasma-Themes/ 2>/dev/null || echo "WARN: failed to copy Beauty-Plasma-Themes"
    rm -rf /tmp/beauty
else
    echo "WARN: Failed to clone Beauty-Plasma-Themes"
fi

# Install macOS cursor themes from binary release
if curl -L -f -o /tmp/macOS-BigSur.tar.gz https://github.com/ful1e5/apple_cursor/releases/download/v2.0.0/macOS-BigSur.tar.gz; then
    tar -xzf /tmp/macOS-BigSur.tar.gz -C /usr/share/icons/ || echo "WARN: failed to extract BigSur cursor"
    rm -f /tmp/macOS-BigSur.tar.gz
else
    echo "WARN: Failed to download BigSur cursor theme"
fi

if curl -L -f -o /tmp/macOS-Monterey.tar.gz https://github.com/ful1e5/apple_cursor/releases/download/v2.0.0/macOS-Monterey.tar.gz; then
    tar -xzf /tmp/macOS-Monterey.tar.gz -C /usr/share/icons/ || echo "WARN: failed to extract Monterey cursor"
    rm -f /tmp/macOS-Monterey.tar.gz
else
    echo "WARN: Failed to download Monterey cursor theme"
fi

echo "Themes installed successfully"
