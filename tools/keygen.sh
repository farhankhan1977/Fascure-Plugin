#!/bin/bash
# Build a Fascure Node.js App license key.
# The RSA private key never belongs in this repository.
#
#   FASCURE_LICENSE_PRIVATE_KEY=/path/to/private.pem tools/keygen.sh --host hostname --plan basic|standard|enterprise [--exp unix]
#
# Plans:
#   basic      1 account,  1 application on that account
#   standard   10 accounts, 3 applications on each account
#   enterprise unlimited accounts and applications
set -euo pipefail

host=""
plan=""
exp="0"
key="${FASCURE_LICENSE_PRIVATE_KEY:-}"
if [[ -z "$key" && -f /root/fascure-license/private.pem ]]; then
    key="/root/fascure-license/private.pem"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) host="${2:-}"; shift 2 ;;
        --plan) plan="${2:-}"; shift 2 ;;
        --exp) exp="${2:-}"; shift 2 ;;
        --private-key) key="${2:-}"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$host" || -z "$plan" || -z "$key" || ! -f "$key" ]]; then
    echo "Usage: FASCURE_LICENSE_PRIVATE_KEY=/path/to/private.pem tools/keygen.sh --host hostname --plan basic|standard|enterprise [--exp unix]" >&2
    exit 1
fi
if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Hostname is not valid." >&2
    exit 1
fi
if [[ ! "$exp" =~ ^[0-9]+$ ]]; then
    echo "Expiry must be a unix time, or 0 when the key does not expire." >&2
    exit 1
fi

case "$plan" in
    basic) tenants=1; apps=1 ;;
    standard) tenants=10; apps=3 ;;
    enterprise) tenants=0; apps=0 ;;
    *) echo "Plan must be basic, standard, or enterprise." >&2; exit 1 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
aes="$(tr -d '[:space:]' < "$root/lib/license-aes.hex")"
hmac="$(tr -d '[:space:]' < "$root/lib/license-hmac.hex")"
id="$(openssl rand -hex 8)"
iv="$(openssl rand -hex 16)"
payload=$(printf '{"product":"fascure-nodeapps","plan":"%s","host":"%s","tenants":%s,"apps":%s,"exp":%s,"id":"%s"}' "$plan" "$host" "$tenants" "$apps" "$exp" "$id")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$payload" > "$tmp/plain"
openssl enc -aes-256-cbc -K "$aes" -iv "$iv" -nosalt -in "$tmp/plain" -out "$tmp/cipher" >/dev/null 2>&1
perl -e 'open my $o, ">", $ARGV[2] or die $!; binmode $o; print {$o} pack("H*", $ARGV[0]); open my $c, "<", $ARGV[1] or die $!; binmode $c; local $/; print {$o} <$c>;' "$iv" "$tmp/cipher" "$tmp/mac-in"
openssl dgst -sha256 -mac HMAC -macopt "hexkey:$hmac" -binary -out "$tmp/mac" "$tmp/mac-in" >/dev/null 2>&1
perl -e 'open my $o, ">", $ARGV[2] or die $!; binmode $o; open my $m, "<", $ARGV[0] or die $!; binmode $m; local $/; my $mac = <$m>; die "bad mac\n" unless length($mac) == 32; print {$o} pack("H*", $ARGV[1]), $mac; open my $c, "<", $ARGV[3] or die $!; binmode $c; print {$o} <$c>;' "$tmp/mac" "$iv" "$tmp/blob" "$tmp/cipher"
openssl dgst -sha256 -sign "$key" -out "$tmp/sig" "$tmp/blob" >/dev/null 2>&1
perl -MMIME::Base64 -e '
sub b64url {
    my $s = encode_base64($_[0], "");
    $s =~ tr{+/}{-_};
    $s =~ s/=+\z//;
    return $s;
}
sub slurp {
    open my $fh, "<", $_[0] or die $!;
    binmode $fh;
    local $/;
    return scalar <$fh>;
}
print "FSC2.", b64url(slurp($ARGV[0])), ".", b64url(slurp($ARGV[1])), "\n";
' "$tmp/blob" "$tmp/sig"
