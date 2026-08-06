#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Configuring GNOME theming ==="

install -d -m 0755 /etc/environment.d
cat >/etc/environment.d/10-vibes-qt.conf <<'EOF'
QT_QPA_PLATFORMTHEME=gtk3
EOF

install -d -m 0755 /etc/dconf/db/local.d
cat >/etc/dconf/db/local.d/01-vibes-gtk <<'EOF'
[org/gnome/desktop/interface]
gtk-theme='adw-gtk-dark'
icon-theme='MoreWaita'
EOF

if [[ ! -f /etc/dconf/profile/user ]]; then
  echo 'user-db:user' >/etc/dconf/profile/user
  echo 'system-db:local' >>/etc/dconf/profile/user
elif ! grep -q 'system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  echo 'system-db:local' >>/etc/dconf/profile/user
fi

echo "--- GNOME theming configured ---"
