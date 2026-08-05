#!/usr/bin/env bash
# GNOME theming: default GTK3 theme to adw-gtk (libadwaita look) and make
# Qt applications follow the GNOME theme for a native look.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Configuring GNOME theming ==="

# Make Qt applications use the GTK3 platform theme so they render with the
# same theme as native GTK/GNOME applications (Qt5/Qt6 on Fedora ship the
# gtk3 platform theme plugin; apps missing it silently fall back to default).
install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/10-vibes-qt.conf <<'EOF'
# Make Qt applications use the GTK3 theme to match GNOME (adw-gtk/libadwaita).
QT_QPA_PLATFORMTHEME=gtk3
EOF

# Ship adw-gtk as the default GTK3 theme via dconf system defaults. The
# adw-gtk theme flatpaks (org.gtk.Gtk3theme.*) are installed by the recipe's
# default-flatpaks module and exported system-wide by flatpak.
install -d -m 0755 /etc/dconf/db/local.d
cat >/etc/dconf/db/local.d/01-vibes-gtk <<'EOF'
[org/gnome/desktop/interface]
gtk-theme='adw-gtk-dark'
icon-theme='MoreWaita'
EOF

# Ensure the dconf profile includes the local system database. Only append if
# the base image did not already reference it, to avoid overriding its profile.
if [[ ! -f /etc/dconf/profile/user ]]; then
  echo 'user-db:user' >/etc/dconf/profile/user
  echo 'system-db:local' >>/etc/dconf/profile/user
elif ! grep -q 'system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  echo 'system-db:local' >>/etc/dconf/profile/user
fi

echo "--- GNOME theming configured ---"
