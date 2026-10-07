#!/usr/bin/env bash
# Deprecated name — use ingest-and-upload-dip.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/scripts/shell/ingest-and-upload-dip.sh" "$@"
