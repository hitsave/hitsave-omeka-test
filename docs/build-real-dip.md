# Build a real E-ARK DIP and view it in test Omeka

This guide lives in the **hitsave-omeka-test** repository: the local Omeka S instance (port **8088**) used to QA **HitSaveArchive**, **OmekaDipViewer**, and prod mirror behavior. It does **not** build or upload DIPs itself.

Packaging and Omeka upload use the **preservation stack** in [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver) — the same `docker compose` services and **omeka-uploader** path as production and batch ingest. You need three checkouts on one host:

| Checkout | Purpose |
|----------|---------|
| **This repo** (`hitsave-omeka-test`) | Test Omeka + MariaDB (`docker compose` in the clone root) |
| [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver) | Postgres ledger, ClamAV, ingest worker, omeka-uploader |
| [**hitsave-archiver-config**](https://github.com/hitsave/hitsave-archiver-config) (private) | API keys, Wasabi/Moby creds, `preservation/database.yaml` |

Typical sibling layout:

```text
~/hitsave-archiver/
~/hitsave-archiver-config/
~/hitsave-omeka-test/          ← you are here
```

---

## One-time setup

### A. Private config and host paths

Create **`hitsave-archiver-config`** (private git repo or any directory) using the committed **`*.example`** files in [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver). Canonical file list, manual `cp` commands, and what stays in the public clone: **[operator-config.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/operator-config.md)**.

Quick bootstrap from the public archiver clone (copies secrets + `database.yaml` into a sibling private dir):

```bash
cd ~/hitsave-archiver
./scripts/ensure-local-config.sh
```

Then copy host path exports and edit **every** copied secret (replace placeholders):

```bash
cp ~/hitsave-archiver/config/host.env.example ~/hitsave-archiver-config/host.env
# Edit HITSAVE_PRIVATE_CONFIG, HOST_PRESS_MATERIAL, HOST_SUBMISSIONS, HOST_OUTPUT
source ~/hitsave-archiver-config/host.env
```

| Variable | Role |
|----------|------|
| `HITSAVE_PRIVATE_CONFIG` | Path to your private config directory |
| `HOST_PRESS_MATERIAL` | Press-material on the host → `/data/press-material` in the worker |
| `HOST_OUTPUT` | AIP/DIP output → `/output` in the worker; DIPs under `$HOST_OUTPUT/dip/` |
| `HOST_SUBMISSIONS` | Optional zip intake → `/data/submissions` |

For test Omeka upload you need **`secrets/omeka-api-credentials-local.yaml`** in that private tree — copy from [`config/secrets/omeka-api-credentials-local.yaml.example`](https://github.com/hitsave/hitsave-archiver/blob/main/config/secrets/omeka-api-credentials-local.yaml.example) and create an Omeka S API key. The uploader uses public [`config/omeka-uploader.yaml`](https://github.com/hitsave/hitsave-archiver/blob/main/config/omeka-uploader.yaml) (default `http://host.docker.internal:8088/api` when test Omeka runs on the same host).

Start long-lived preservation services (with `host.env` sourced):

```bash
cd ~/hitsave-archiver
python3 scripts/sync-preservation-config.py
docker compose up -d postgres clamav
```

### B. Test Omeka (this repository)

From the **root of this clone**:

```bash
./scripts/ensure-local-config.sh
./scripts/shell/run-omeka-test.sh
```

Edit **`config/omeka-test/settings.yaml`** (created from the example) for admin password, `omeka.public_url`, and `omeka.site_slug`. SSOT map: **[config-contract.md](./config-contract.md)**. Keep `api:` in sync with hitsave-archiver **`config/omeka-uploader.yaml`** when uploading from Docker.

Optional: when starting this stack, set **`DIP_OUTPUT_ROOT`** to the same host directory as `HOST_OUTPUT` so Compose mounts `$DIP_OUTPUT_ROOT/dip` at `/dip-output` inside Omeka (read-only). That is only for inspecting tars on disk; **omeka-uploader** reads DIPs from the archiver `/output` mount, not from this path.

---

## Per game: ingest then upload

All commands below assume **`source ~/hitsave-archiver-config/host.env`** (or your `host.env` path) and **`cd ~/hitsave-archiver`**.

### 1. Configure `game.yml`

In the **hitsave-archiver** clone (not the private config repo):

```bash
cp config/preservation/game.yml.example config/preservation/game.yml
```

Edit for a real folder under press material (paths are **inside the ingest-worker container**):

```yaml
source_game_folder: /data/press-material/Publisher/GameName
output_tar: /output/dip/game-name.tar
game_key: game-name
omeka_item_title: "Game Name — press and marketing materials"
```

Zip intake instead of press-material: [portable-submissions.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/portable-submissions.md) in the archiver repo.

### 2. Ingest (AIP + DIP on disk)

```bash
docker compose run --rm ingest-worker /config/preservation/game.yml
```

This updates the Postgres ledger for `game_key` and writes **`$HOST_OUTPUT/dip/<name>.tar`** on the host.

### 3. Upload to test Omeka

Test Omeka must already be running (setup **B**). From the same archiver directory:

```bash
docker compose run --rm omeka-uploader game-name /config/preservation/game.yml
```

The uploader sends the tar over the Omeka REST API (multipart), ingester **`omeka_dip_package`**, honors **`config/omeka-uploader.yaml`** (site slug, item set, default visibility), may attach Moby fields from the ledger, and stores Omeka item/media ids on `game_ingest`. Batch jobs use the same service via `scripts/run-batch-resume-omeka.sh` in the archiver repo.

---

## Verify

Use **`config/omeka-test/settings.yaml`** in **this repo** for URLs and credentials:

- **Admin:** `{public_url}/admin` — new item with media ingester **`omeka_dip_package`** (uploads are usually **private** until you publish).
- **Public site:** `{public_url}/s/{site_slug}/...` (default site slug `hitsave-test` unless you changed it).

For production vs test behavior (ARKs, visibility, prod mirror), see [omeka-production.md](./omeka-production.md).
