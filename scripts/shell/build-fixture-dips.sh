#!/usr/bin/env bash
# Build E-ARK DIP fixture tars (sample-game + large threshold test) via hitsave-archiver ingest-worker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVER="${HITSAVE_ARCHIVER_ROOT:-$ROOT/../hitsave-archiver}"

SRC="$ROOT/fixtures/dips/sources/sample-game"
mkdir -p "$SRC"
for f in readme.txt screenshot.jpg trailer.mp4; do
  if [[ ! -f "$SRC/$f" ]]; then
    echo "Missing fixture source $SRC/$f — add small sample files or extract from an existing sample-game.tar" >&2
    exit 1
  fi
done

FIXTURE_CFG="$ROOT/config/omeka-test/fixture-sample-game.yaml"
if [[ ! -f "$ARCHIVER/docker-compose.yml" ]]; then
  echo "Set HITSAVE_ARCHIVER_ROOT to a hitsave-archiver clone (default: $ARCHIVER)" >&2
  exit 1
fi

docker compose -f "$ARCHIVER/docker-compose.yml" build ingest-worker >/dev/null
docker compose -f "$ARCHIVER/docker-compose.yml" run --rm --entrypoint python \
  -v "$ROOT/fixtures:/fixtures" \
  -v "$FIXTURE_CFG:/fixture.yaml:ro" \
  ingest-worker \
  /app/scripts/build-dip-e-ark.py /fixture.yaml

LARGE="$ROOT/fixtures/dips/built/large-sample.tar"
SAMPLE="$ROOT/fixtures/dips/built/sample-game.tar"
TMP=$(mktemp -d)
tar -xf "$SAMPLE" -C "$TMP"
dd if=/dev/zero of="$TMP/representations/rep1/data/large-padding.bin" bs=1M count=512 status=none 2>/dev/null
tar --format=ustar -cf "$LARGE" -C "$TMP" .
rm -rf "$TMP"
echo "Built $SAMPLE and $LARGE ($(stat -c%s "$SAMPLE") / $(stat -c%s "$LARGE") bytes)"
