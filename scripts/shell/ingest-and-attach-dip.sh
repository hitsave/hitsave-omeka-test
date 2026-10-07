#!/usr/bin/env bash
# Build DIP via hitsave-archiver ingest, then upload to local Omeka test stack (QA helper).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVER="${HITSAVE_ARCHIVER_ROOT:-$ROOT/../hitsave-archiver}"
GAME_CFG="${1:-config/preservation/game.yml}"

cd "$ARCHIVER"
if [[ ! -f "$GAME_CFG" ]]; then
  echo "Missing $GAME_CFG — copy config/preservation/game.yml.example and edit (see docs/build-real-dip.md)" >&2
  exit 1
fi

export HITSAVE_PRIVATE_CONFIG="${HITSAVE_PRIVATE_CONFIG:-$ARCHIVER/../hitsave-archiver-config}"
python3 scripts/sync-preservation-config.py
docker compose run --rm ingest-worker "/config/preservation/${GAME_CFG#config/preservation/}"

TAR_NAME="$(python3 -c "import yaml; print(yaml.safe_load(open('$GAME_CFG'))['output_tar'].split('/')[-1])")"
TITLE="$(python3 -c "import yaml; print(yaml.safe_load(open('$GAME_CFG'))['omeka_item_title'])")"

cd "$ROOT"
exec "$ROOT/scripts/shell/attach-dip-from-output.sh" "$TAR_NAME" "$TITLE"
