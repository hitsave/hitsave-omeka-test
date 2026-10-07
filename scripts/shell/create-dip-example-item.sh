#!/usr/bin/env bash
# Deprecated wrapper — use attach-dip-from-output.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/shell/attach-dip-from-output.sh" "$@"
