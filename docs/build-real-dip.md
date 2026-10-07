# Build a real E-ARK DIP and view it in test Omeka

Test Omeka does not ship synthetic fixture packages. DIPs come from the same **hitsave-archiver** ingest path used in production: a folder of press material (or a portable submission) → ClamAV → E-ARK AIP/DIP on the output volume.

## Prerequisites

Sibling clones (paths adjustable via env vars):

```text
hitsave-archiver/
hitsave-archiver-config/   # private secrets + database.yaml
hitsave-omeka-test/        # this repo — Omeka on :8088
```

On your host, example paths (adjust to your layout):

| Variable | Example |
|----------|---------|
| `HOST_PRESS_MATERIAL` | `/tank2/press-material` |
| `HOST_OUTPUT` / `DIP_OUTPUT_ROOT` | `/tank/hitsave-archiver/output` |
| `HITSAVE_PRIVATE_CONFIG` | `../hitsave-archiver-config` (or an absolute path) |

Start preservation services and the test Omeka stack:

```bash
cd hitsave-archiver
export HITSAVE_PRIVATE_CONFIG=../hitsave-archiver-config
export HOST_PRESS_MATERIAL=/tank2/press-material
export HOST_OUTPUT=/tank/hitsave-archiver/output
./scripts/ensure-local-config.sh
python3 scripts/sync-preservation-config.py
docker compose up -d postgres clamav

cd ../hitsave-omeka-test
./scripts/ensure-local-config.sh
./scripts/shell/run-omeka-test.sh
```

## 1. Point ingest at real content

In **hitsave-archiver**, copy the template and edit paths to a real game folder under press material:

```bash
cd hitsave-archiver
cp config/preservation/game.yml.example config/preservation/game.yml
# Edit source_game_folder, game_key, omeka_item_title, output_tar name
```

Example fields (container paths — match `docker-compose.yml` mounts):

```yaml
source_game_folder: /data/press-material/Publisher/GameName
output_tar: /output/dip/game-name.tar
game_key: game-name
omeka_item_title: "Game Name — press and marketing materials"
```

See also [portable submissions](https://github.com/hitsave/hitsave-archiver/blob/main/docs/portable-submissions.md) if the source is a zip under `/data/submissions/incoming/` instead of press-material.

## 2. Run ingest (build AIP + DIP)

```bash
cd hitsave-archiver
docker compose run --rm ingest-worker /config/preservation/game.yml
```

On success the DIP tar is on the host at:

```text
${HOST_OUTPUT}/dip/<name>.tar
```

(same tree mounted read-only in Omeka as `/dip-output/`).

## 3. Attach the DIP on test Omeka (browse in place)

From **hitsave-omeka-test**:

```bash
./scripts/shell/attach-dip-from-output.sh game-name.tar "Game Name — press and marketing materials"
```

Or run ingest + attach in one step:

```bash
./scripts/shell/ingest-and-attach-dip.sh
```

(`ingest-and-attach-dip.sh` uses `hitsave-archiver/config/preservation/game.yml` by default.)

## 4. Upload via REST (production-like)

Skip manual attach; use the archiver uploader after ingest:

```bash
cd hitsave-archiver
docker compose run --rm omeka-uploader <game_key> /config/preservation/game.yml
```

Configure the API target in **hitsave-archiver** `config/omeka-uploader.yaml` (test stack: `host.docker.internal:8088`). Credentials live in **hitsave-archiver-config**.

## Verify

- Admin: `{public_url}/admin` — item with ingester **DIP package (browse in place)**.
- Public site: `{public_url}/s/hitsave-test/...` (see `config/omeka-test/settings.yaml`).
