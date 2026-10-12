# Build a BagIt package and view it in test Omeka

Local Omeka S on port **8088** for QA. Packaging and upload run in [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver).

| Checkout | Purpose |
|----------|---------|
| **This repo** (`hitsave-omeka-test`) | Test Omeka + MariaDB |
| [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver) | Postgres ledger, ClamAV, ingest worker, omeka-catalog |
| [**hitsave-archiver-config**](https://github.com/hitsave/hitsave-archiver-config) (private) | API keys, Wasabi/Moby creds |

---

## One-time setup

### A. Private config and host paths

Follow [**operator-config.md**](https://github.com/hitsave/hitsave-archiver/blob/main/docs/operator-config.md) in the archiver repo. Source `host.env` with `HITSAVE_PRIVATE_CONFIG`, `HOST_PRESS_MATERIAL`, `HOST_OUTPUT`, etc.

Start preservation services:

```bash
cd ~/hitsave-archiver
python3 scripts/sync-preservation-config.py
docker compose up -d postgres clamav
```

### B. Test Omeka + Wasabi S3

```bash
cd ~/hitsave-omeka-test
./scripts/ensure-local-config.sh
python3 scripts/shell/render-dip-s3-config.py \
  --wasabi-credentials "$HITSAVE_PRIVATE_CONFIG/secrets/wasabi-credentials.yaml" \
  --output ../omeka-dip-viewer/config/dip-s3.config.php
docker compose -f docker-compose.yml -f docker-compose.s3-direct.yml build omeka
./scripts/shell/run-omeka-test.sh
```

Details: [dip-wasabi-s3-direct.md](./dip-wasabi-s3-direct.md).

Optional: mount `$HOST_OUTPUT/bag` at `/dip-output` for inspecting local bags (Omeka browse uses Wasabi, not this mount).

---

## Per game: ingest then upload

From **`~/hitsave-archiver`** with `host.env` sourced:

### 1. Configure `game.yml`

```yaml
source_game_folder: /data/press-material/Publisher/GameName
game_key: game-name
omeka_item_title: "Game Name — press and marketing materials"
```

Paths are **inside the ingest-worker container**.

### 2. Ingest

```bash
docker compose run --rm ingest-worker /config/preservation/game.yml
```

Writes a BagIt directory under `$HOST_OUTPUT/bag/…` and syncs an unpacked prefix to Wasabi.

### 3. Register DIP in test Omeka

```bash
docker compose run --rm omeka-catalog game-name /config/preservation/game.yml
```

Creates an Omeka item + `omeka_dip_package` media pointing at the Wasabi prefix (no multipart tar upload).

---

## Verify

- **Admin:** item with ingester **`omeka_dip_package`**
- **Browse:** carousel, lightbox, and file streams load from S3

See [omeka-production.md](./omeka-production.md) for production vs test.
