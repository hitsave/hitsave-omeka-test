#!/usr/bin/env bash
# Upload an existing preservation DIP .tar to test Omeka (from /dip-output in the container).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dip-filename.tar> [omeka_item_title]" >&2
  echo "  DIP must exist on host under \${DIP_OUTPUT_ROOT:-/tank/hitsave-archiver/output}/dip/" >&2
  exit 1
fi

TAR="$1"
TITLE="${2:-}"
CONTAINER_PATH="/dip-output/$(basename "$TAR")"

docker compose exec -T omeka php /scripts/ensure-omeka-test-site.php
if [[ -n "$TITLE" ]]; then
  docker compose exec -T omeka php /scripts/create-dip-example-item.php "$CONTAINER_PATH" "$TITLE"
else
  docker compose exec -T omeka php /scripts/create-dip-example-item.php "$CONTAINER_PATH"
fi
