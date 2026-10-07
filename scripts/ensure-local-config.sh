#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

copy_if_missing() {
  local example="$1"
  local target="$2"
  if [[ -f "$target" ]]; then
    return 0
  fi
  if [[ ! -f "$example" ]]; then
    echo "Missing $example (cannot create $target)" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  cp "$example" "$target"
  echo "Created $target from $(basename "$example") — edit before use."
}

copy_if_missing "$ROOT/config/omeka-test/settings.example.yaml" "$ROOT/config/omeka-test/settings.yaml"
copy_if_missing "$ROOT/config/omeka-test/database.ini.example" "$ROOT/config/omeka-test/database.ini"
copy_if_missing "$ROOT/config/omeka-test/omeka-prod-source.yaml.example" "$ROOT/config/omeka-test/omeka-prod-source.yaml"
copy_if_missing "$ROOT/config/omeka-test/sample-from-prod.yaml.example" "$ROOT/config/omeka-test/sample-from-prod.yaml"

python3 "$ROOT/scripts/shell/sync-docker-config.py"

echo "Preservation secrets: build hitsave-archiver-config from hitsave-archiver config/**/*.example (docs/operator-config.md)."
echo "Omeka upload API key: secrets/omeka-api-credentials-local.yaml in that private dir."
