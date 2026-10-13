#!/bin/bash
# Compatibility wrapper. Prefer tools/keygen.sh.
set -euo pipefail
host="${1:-}"
plan="${2:-enterprise}"
exp="${3:-0}"
exec "$(cd "$(dirname "$0")" && pwd)/keygen.sh" --host "$host" --plan "$plan" --exp "$exp"
