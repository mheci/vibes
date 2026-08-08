#!/usr/bin/env bash
# vjust dns-encrypted helper: enable encrypted DNS (DNS over TLS)
# through systemd-resolved. Defaults to Cloudflare; a custom resolver
# (e.g. 9.9.9.9 or a local stub) can be passed as the first argument.
set -euo pipefail

RESOLVER="${1:-1.1.1.1}"
install -d -m 0755 /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/encrypted-dns.conf <<CONF
[Resolve]
DNS=${RESOLVER} 1.1.1.1 1.0.0.1
DNSOverTLS=yes
CONF
systemctl restart systemd-resolved
echo "Encrypted DNS enabled: ${RESOLVER} (DoT)"
echo "Verify with: resolvectl status"
