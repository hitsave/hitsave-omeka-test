# Build a real E-ARK DIP and view it in test Omeka

Test Omeka does not ship synthetic fixture packages. DIPs come from the same **hitsave-archiver** ingest path used in production: a folder of press material (or a portable submission) → ClamAV → E-ARK AIP/DIP on the output volume → **omeka-uploader** sends the `.tar` to Omeka (same as batch production).

## Prerequisites

Sibling clones (paths adjustable via env vars):

```text
hitsave-archiver/
hitsave-archiver-config/   # private secrets + database.yaml + Omeka API keys
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

Ensure **hitsave-archiver-config** has a working `secrets/omeka-api-credentials-local.yaml` (see archiver `config/secrets/*.example`). `config/omeka-uploader.yaml` in the public archiver repo points the uploader at test Omeka (`host.docker.internal:8088`).

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

This creates a **ledger row** for `game_key` and writes the DIP tar on the host at `${HOST_OUTPUT}/dip/<name>.tar` (also visible in the test Omeka container as `/dip-output/` read-only).

## 3. Upload the DIP to Omeka (preservation uploader)

One game after ingest:

```bash
cd hitsave-archiver
docker compose run --rm omeka-uploader game-name /config/preservation/game.yml
```

Ingest + upload in one step (from **hitsave-omeka-test**, uses archiver `game.yml`):

```bash
./scripts/shell/ingest-and-upload-dip.sh
```

The uploader uses the Omeka **REST API** (multipart), the **DIP package (browse in place)** ingester, **`config/omeka-uploader.yaml`** (site slug, item set, default visibility), optional **Moby** fields from the ledger, and records **omeka_item_id** / **omeka_media_id** on `game_ingest`. Batch runs use the same uploader via `scripts/run-batch-resume-omeka.sh`.

## Verify

- Admin: `{public_url}/admin` — item with ingester **DIP package (browse in place)** (test config usually keeps uploads **private** until you publish).
- Public site: `{public_url}/s/hitsave-test/...` (see `config/omeka-test/settings.yaml`).

## Legacy: in-container upload script

`scripts/shell/attach-dip-from-output.sh` (PHP helper inside the Omeka container) predates the split and **duplicates** the uploader at the Omeka layer only. It skips the ledger, item set, Moby metadata, and REST credentials, and creates **public** items. Prefer **omeka-uploader** for anything that should match production.
