#!/bin/bash
# Issue a Fascure Node.js App license key for one server hostname.
# The private key is not part of this repository.
#
#   FASCURE_LICENSE_PRIVATE_KEY=/path/to/private.pem tools/issue-license.sh hostname [expiry_unix]
#
# expiry_unix is 0 when the key does not expire.
set -euo pipefail

host="${1:-}"
exp="${2:-0}"
key="${FASCURE_LICENSE_PRIVATE_KEY:-}"

if [[ -z "$host" || -z "$key" || ! -f "$key" ]]; then
    echo "Usage: FASCURE_LICENSE_PRIVATE_KEY=/path/to/private.pem tools/issue-license.sh hostname [expiry_unix]" >&2
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

payload=$(printf '{"product":"fascure-nodeapps","host":"%s","exp":%s}' "$host" "$exp")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$payload" > "$tmp/payload"
openssl dgst -sha256 -sign "$key" -out "$tmp/sig" "$tmp/payload" >/dev/null
perl -MMIME::Base64 -e '
sub b64url {
    my $s = encode_base64($_[0], "");
    $s =~ tr{+/}{-_};
    $s =~ s/=+\z//;
    return $s;
}
open my $p, "<", $ARGV[0] or die $!;
local $/;
my $payload = <$p>;
close $p;
open my $s, "<", $ARGV[1] or die $!;
binmode $s;
my $sig = <$s>;
close $s;
print "FSC1.", b64url($payload), ".", b64url($sig), "\n";
' "$tmp/payload" "$tmp/sig"
