#!/usr/bin/env bash
# Ingest one game (hitsave-archiver), then upload DIP via omeka-uploader (production path).
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
docker compose up -d postgres >/dev/null
docker compose run --rm ingest-worker "/config/preservation/${GAME_CFG#config/preservation/}"

GAME_KEY="$(python3 -c "import yaml; print(yaml.safe_load(open('$GAME_CFG'))['game_key'])")"
exec docker compose run --rm omeka-uploader "$GAME_KEY" "/config/preservation/${GAME_CFG#config/preservation/}"
