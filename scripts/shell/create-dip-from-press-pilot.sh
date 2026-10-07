#!/usr/bin/env bash
# Build DIP via hitsave-archiver ingest, then attach on local Omeka test stack.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVER="${HITSAVE_ARCHIVER_ROOT:-$ROOT/../hitsave-archiver}"
GAME_CFG="config/preservation/game.yml"

cd "$ARCHIVER"
if [[ ! -f "$GAME_CFG" ]]; then
  echo "Copy config/preservation/game.yml.example to $GAME_CFG in hitsave-archiver" >&2
  exit 1
fi

export HITSAVE_PRIVATE_CONFIG="${HITSAVE_PRIVATE_CONFIG:-$ARCHIVER/../hitsave-archiver-config}"
python3 scripts/sync-preservation-config.py
docker compose run --rm ingest-worker "/config/preservation/game.yml"

cd "$ROOT"
TAR_HOST="$(python3 -c "
import yaml
from pathlib import Path
p = yaml.safe_load(open('$ARCHIVER/$GAME_CFG'))['output_tar']
print(str(Path('${DIP_OUTPUT_ROOT:-/tank/hitsave-archiver/output}') / p.removeprefix('/output/').lstrip('/')))
")"
TITLE="$(python3 -c "import yaml; print(yaml.safe_load(open('$ARCHIVER/$GAME_CFG'))['omeka_item_title'])")"

docker compose exec -T omeka php /scripts/ensure-omeka-test-site.php
docker compose exec -T omeka php /scripts/create-dip-example-item.php "/dip-output/$(basename "$TAR_HOST")" "$TITLE"
