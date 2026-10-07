# Build a real E-ARK DIP and view it in test Omeka

DIPs are built and uploaded only through **hitsave-archiver** Docker Compose (ingest worker + **omeka-uploader**). This repo runs test Omeka on `:8088`; it does not wrap ingest or upload.

## Repos and host configuration

```text
hitsave-archiver/           # ingest + upload commands (run here)
hitsave-archiver-config/    # secrets, database.yaml, Omeka API keys
hitsave-omeka-test/         # MariaDB + Omeka (this repo)
```

Copy **hitsave-archiver-config** `host.env.example` → `host.env`, set paths, then source it before any archiver `docker compose` command:

```bash
cd hitsave-archiver-config
cp host.env.example host.env
# Edit: HITSAVE_PRIVATE_CONFIG, HOST_PRESS_MATERIAL, HOST_SUBMISSIONS, HOST_OUTPUT
source host.env
```

| Variable | Role |
|----------|------|
| `HITSAVE_PRIVATE_CONFIG` | Private repo checkout (mounted at `/config/secrets` and `database.yaml`) |
| `HOST_PRESS_MATERIAL` | Press-material tree (read-only in ingest worker) |
| `HOST_OUTPUT` | AIP/DIP output; DIPs under `$HOST_OUTPUT/dip/` |
| `HOST_SUBMISSIONS` | Optional portable zip intake |

From **hitsave-archiver** after sourcing `host.env`:

```bash
./scripts/ensure-local-config.sh
python3 scripts/sync-preservation-config.py
docker compose up -d postgres clamav
```

Test Omeka (separate compose project):

```bash
cd hitsave-omeka-test
./scripts/ensure-local-config.sh
./scripts/shell/run-omeka-test.sh
```

**Omeka API for upload:** create `secrets/omeka-api-credentials-local.yaml` in the private repo (see archiver `config/secrets/*.example`). Public **`config/omeka-uploader.yaml`** targets test Omeka at `http://host.docker.internal:8088/api` when the uploader runs in Docker on the same host as the test stack.

Set **`DIP_OUTPUT_ROOT`** to the same directory as `HOST_OUTPUT` when starting **hitsave-omeka-test** so `/dip-output` inside Omeka matches archiver output (read-only; useful for inspection, not required for uploader).

## 1. Point ingest at real content

In **hitsave-archiver** (with `host.env` sourced):

```bash
cp config/preservation/game.yml.example config/preservation/game.yml
# Edit source_game_folder, game_key, omeka_item_title, output_tar
```

Example (paths inside the ingest-worker container):

```yaml
source_game_folder: /data/press-material/Publisher/GameName
output_tar: /output/dip/game-name.tar
game_key: game-name
omeka_item_title: "Game Name — press and marketing materials"
```

Portable zip intake: [portable-submissions.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/portable-submissions.md).

## 2. Ingest (AIP + DIP)

```bash
cd hitsave-archiver
docker compose run --rm ingest-worker /config/preservation/game.yml
```

Creates a ledger row for `game_key` and writes `${HOST_OUTPUT}/dip/<name>.tar`.

## 3. Upload to test Omeka

```bash
cd hitsave-archiver
docker compose run --rm omeka-uploader game-name /config/preservation/game.yml
```

Same **omeka-uploader** service as batch production (`scripts/run-batch-resume-omeka.sh`): REST multipart, ingester **`omeka_dip_package`**, `config/omeka-uploader.yaml`, optional Moby fields from the ledger, Omeka ids stored on `game_ingest`.

## Verify

- Admin: `{public_url}/admin` — media ingester **`omeka_dip_package`** (test uploads are usually **private** until published).
- Public site: `{public_url}/s/hitsave-test/...` (`config/omeka-test/settings.yaml`).
