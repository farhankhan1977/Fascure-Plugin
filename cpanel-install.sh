#!/bin/bash
# Install Fascure Node.js App on a cPanel server.
#
# From a clone of this repository:
#   bash cpanel-install.sh
#
# From GitHub:
#   curl -fsSL https://raw.githubusercontent.com/farhankhan1977/Fascure-Plugin/main/cpanel-install.sh | bash
#
# Override the source when needed:
#   FASCURE_NODEAPPS_REPO=https://github.com/farhankhan1977/Fascure-Plugin bash cpanel-install.sh
set -euo pipefail

REPO="${FASCURE_NODEAPPS_REPO:-https://github.com/farhankhan1977/Fascure-Plugin}"
REF="${FASCURE_NODEAPPS_REF:-main}"

here="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [[ -n "$here" && -f "$here/install-FS-plugin.sh" && -f "$here/install.json" ]]; then
    exec bash "$here/install-FS-plugin.sh"
fi

if [[ "$REPO" == *"/OWNER/"* ]]; then
    echo "Set FASCURE_NODEAPPS_REPO to the GitHub repository URL before running this from GitHub." >&2
    echo "Example: FASCURE_NODEAPPS_REPO=https://github.com/farhankhan1977/Fascure-Plugin bash cpanel-install.sh" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${REPO}/archive/refs/heads/${REF}.tar.gz" -o "$tmp/src.tar.gz"
tar -xzf "$tmp/src.tar.gz" -C "$tmp"
src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
bash "$src/install-FS-plugin.sh"
