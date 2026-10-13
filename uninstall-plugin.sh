#!/bin/bash
# Remove Fascure Node.js App from this cPanel server.
# Account application files under each home directory are left in place.
# Pass --remove-node to also delete the Node.js builds in /opt/nodeapps.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this uninstaller as root." >&2
    exit 1
fi

REMOVE_NODE=0
if [[ "${1:-}" == "--remove-node" ]]; then
    REMOVE_NODE=1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
UNREGISTER="/usr/local/cpanel/bin/unregister_appconfig"
UNINSTALL="/usr/local/cpanel/scripts/uninstall_plugin"

if [[ -f /var/cpanel/apps/nodeapps.conf && -x "$UNREGISTER" ]]; then
    "$UNREGISTER" /var/cpanel/apps/nodeapps.conf || true
fi

if [[ -x "$UNINSTALL" && -f "$SRC/install.json" ]]; then
    STAGE="$(mktemp -d)"
    mkdir -p "$STAGE/nodeapps"
    cp "$SRC/install.json" "$STAGE/install.json"
    cp "$SRC/cpanel/nodeapps/nodeapps.svg" "$STAGE/nodeapps.svg"
    cp "$SRC/cpanel/nodeapps/index.live.php" "$STAGE/nodeapps/index.live.php"
    cp "$SRC/cpanel/nodeapps/nodeapps.svg" "$STAGE/nodeapps/nodeapps.svg"
    tar -C "$STAGE" -czf /root/nodeapps-plugin.tar.gz .
    rm -rf "$STAGE"
    "$UNINSTALL" /root/nodeapps-plugin.tar.gz || true
fi

rm -f /usr/local/cpanel/Cpanel/API/NodeApp.pm
rm -rf /usr/local/cpanel/base/frontend/jupiter/nodeapps
rm -f /usr/local/cpanel/base/frontend/jupiter/dynamicui/dynamicui_nodeapps.conf
rm -f /usr/local/cpanel/whostmgr/addonfeatures/nodeapps
rm -rf /usr/local/cpanel/whostmgr/docroot/cgi/nodeapps
rm -f /var/cpanel/apps/nodeapps.conf
rm -f /etc/sudoers.d/nodeapps
rm -f /etc/cron.daily/nodeapps-license
rm -f /usr/local/nodeapps/bin/nodeapps-apply \
    /usr/local/nodeapps/bin/nodeapps-quota \
    /usr/local/nodeapps/bin/nodeapps-license-check
rm -f /usr/local/nodeapps/lib/NodeApps.pm \
    /usr/local/nodeapps/lib/license-public.pem \
    /usr/local/nodeapps/lib/license-aes.hex \
    /usr/local/nodeapps/lib/license-hmac.hex
rm -f /var/cpanel/nodeapps/license.key \
    /var/cpanel/nodeapps/license-cache.json \
    /var/cpanel/nodeapps/license-apps-stopped

if [[ -d /etc/apache2/conf.d/userdata ]]; then
    find /etc/apache2/conf.d/userdata -type f -name nodeapps.conf -delete
    if [[ -x /usr/local/cpanel/scripts/rebuildhttpdconf ]]; then
        /usr/local/cpanel/scripts/rebuildhttpdconf || true
    fi
    if [[ -x /usr/local/cpanel/scripts/restartsrv_httpd ]]; then
        /usr/local/cpanel/scripts/restartsrv_httpd || true
    fi
fi

if [[ "$REMOVE_NODE" -eq 1 ]]; then
    rm -rf /opt/nodeapps
fi

if [[ -x /usr/local/cpanel/scripts/restartsrv_cpsrvd ]]; then
    /usr/local/cpanel/scripts/restartsrv_cpsrvd || true
fi

echo "Fascure Node.js App has been removed from WHM and cPanel."
echo "Application files in each account, such as /home/username/apps, were kept."
if [[ "$REMOVE_NODE" -eq 0 ]]; then
    echo "Node.js builds remain in /opt/nodeapps. Run this script with --remove-node to delete them."
fi
