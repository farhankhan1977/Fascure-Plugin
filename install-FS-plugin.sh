#!/bin/bash
# Install Fascure Node.js App on a cPanel server. Safe to run more than once.
#
# From GitHub:
#   curl -fsSL https://raw.githubusercontent.com/farhankhan1977/Fascure-Plugin/main/install-FS-plugin.sh | bash
#
# From a checkout of this repository:
#   bash install-FS-plugin.sh
set -euo pipefail

REPO="${FASCURE_NODEAPPS_REPO:-https://github.com/farhankhan1977/Fascure-Plugin}"
REF="${FASCURE_NODEAPPS_REF:-main}"
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [[ -z "$here" || ! -f "$here/install.json" ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "${REPO}/archive/refs/heads/${REF}.tar.gz" -o "$tmp/src.tar.gz"
    tar -xzf "$tmp/src.tar.gz" -C "$tmp"
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    bash "$src/install-FS-plugin.sh"
    exit 0
fi

SRC="$here"
CPANEL_PLUGIN="/usr/local/cpanel/scripts/install_plugin"
REGISTER="/usr/local/cpanel/bin/register_appconfig"

if [[ ! -x "$CPANEL_PLUGIN" ]]; then
    echo "cPanel is not installed yet ($CPANEL_PLUGIN is missing)." >&2
    exit 1
fi

install -d -m 0755 /usr/local/nodeapps/lib /usr/local/nodeapps/bin /opt/nodeapps/versions
install -m 0644 "$SRC/lib/NodeApps.pm" /usr/local/nodeapps/lib/NodeApps.pm
install -m 0644 "$SRC/lib/license-public.pem" /usr/local/nodeapps/lib/license-public.pem
install -m 0644 "$SRC/lib/license-aes.hex" /usr/local/nodeapps/lib/license-aes.hex
install -m 0644 "$SRC/lib/license-hmac.hex" /usr/local/nodeapps/lib/license-hmac.hex
install -m 0755 "$SRC/bin/nodeapps-apply" /usr/local/nodeapps/bin/nodeapps-apply
install -m 0755 "$SRC/bin/nodeapps-quota" /usr/local/nodeapps/bin/nodeapps-quota
install -m 0755 "$SRC/bin/nodeapps-license-check" /usr/local/nodeapps/bin/nodeapps-license-check
install -m 0755 "$SRC/bin/nodeapps-license-check" /etc/cron.daily/nodeapps-license
install -m 0755 "$SRC/bin/nodeapps-cpu" /usr/local/nodeapps/bin/nodeapps-cpu
install -m 0755 "$SRC/uninstall-FS-plugin.sh" /usr/local/nodeapps/bin/uninstall-FS-plugin.sh
install -d -m 0755 /usr/local/nodeapps/uninstall
install -m 0644 "$SRC/install.json" /usr/local/nodeapps/uninstall/install.json
install -m 0644 "$SRC/cpanel/nodeapps/index.live.php" /usr/local/nodeapps/uninstall/index.live.php
install -m 0644 "$SRC/cpanel/nodeapps/nodeapps.svg" /usr/local/nodeapps/uninstall/nodeapps.svg
cat > /etc/cron.d/nodeapps-cpu <<'EOF'
* * * * * root /usr/local/nodeapps/bin/nodeapps-cpu --apply >/dev/null 2>&1
EOF
chmod 0644 /etc/cron.d/nodeapps-cpu
cat > /etc/sudoers.d/nodeapps <<'EOF'
Defaults!/usr/local/nodeapps/bin/nodeapps-apply !requiretty
Defaults!/usr/local/nodeapps/bin/nodeapps-quota !requiretty
Defaults!/usr/local/nodeapps/bin/nodeapps-license-check !requiretty
ALL ALL=(root) NOPASSWD: /usr/local/nodeapps/bin/nodeapps-apply
ALL ALL=(root) NOPASSWD: /usr/local/nodeapps/bin/nodeapps-quota
ALL ALL=(root) NOPASSWD: /usr/local/nodeapps/bin/nodeapps-license-check
EOF
chmod 0440 /etc/sudoers.d/nodeapps
visudo -cf /etc/sudoers.d/nodeapps
install -d -m 0755 /usr/local/cpanel/Cpanel/API
install -m 0644 "$SRC/api/NodeApp.pm" /usr/local/cpanel/Cpanel/API/NodeApp.pm

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/nodeapps"
cp "$SRC/install.json" "$STAGE/install.json"
cp "$SRC/cpanel/nodeapps/nodeapps.svg" "$STAGE/nodeapps.svg"
cp "$SRC/cpanel/nodeapps/index.live.php" "$STAGE/nodeapps/index.live.php"
cp "$SRC/cpanel/nodeapps/nodeapps.svg" "$STAGE/nodeapps/nodeapps.svg"
tar -C "$STAGE" -czf /root/nodeapps-plugin.tar.gz .
"$CPANEL_PLUGIN" /root/nodeapps-plugin.tar.gz

install -d -m 0755 /usr/local/cpanel/base/frontend/jupiter/nodeapps
install -m 0644 "$SRC/cpanel/nodeapps/index.live.php" /usr/local/cpanel/base/frontend/jupiter/nodeapps/index.live.php
install -m 0644 "$SRC/cpanel/nodeapps/nodeapps.svg" /usr/local/cpanel/base/frontend/jupiter/nodeapps/nodeapps.svg

install -d -m 0755 /usr/local/cpanel/whostmgr/docroot/cgi/nodeapps
install -m 0755 "$SRC/whm/index.cgi" /usr/local/cpanel/whostmgr/docroot/cgi/nodeapps/index.cgi
install -d -m 0755 /var/cpanel/apps
install -m 0644 "$SRC/whm/nodeapps.conf" /var/cpanel/apps/nodeapps.conf
if [[ -x "$REGISTER" ]]; then
    "$REGISTER" /var/cpanel/apps/nodeapps.conf || true
fi

if [[ -x /usr/local/cpanel/scripts/restartsrv_cpsrvd ]]; then
    /usr/local/cpanel/scripts/restartsrv_cpsrvd || true
fi

rm -f /etc/apache2/conf.d/zzz-nodeapps-passenger.conf

echo "Node.js / Next.js plugin files are installed."
echo "Open WHM -> Fascure Node.js App and save a license key before customers can create applications."
echo "Uninstall later with: bash /usr/local/nodeapps/bin/uninstall-FS-plugin.sh"
