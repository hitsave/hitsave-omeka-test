# Config contract — single source of truth (SSOT)

## This repo (hitsave-omeka-test)

| Topic | File | Notes |
|-------|------|--------|
| Admin, DB, public URL, site slug, batch listing page | **`config/omeka-test/settings.yaml`** (from [`settings.example.yaml`](../config/omeka-test/settings.example.yaml)) | Merged with optional `settings.local.yaml`; rendered to `generated.env` by [`sync-docker-config.py`](../scripts/shell/sync-docker-config.py). **Omeka DIP Viewer** tuning is Omeka admin only ([omeka-dip-viewer config-contract](https://github.com/hitsave/omeka-dip-viewer/blob/main/docs/config-contract.md)). |
| REST API for **local Python tools** | **`settings.yaml` → `api:`** | `site_slug` / `item_set_title` default from `omeka:` when omitted |
| Prod mirror source | **`config/omeka-test/omeka-prod-source.yaml`** (from example) | `mirror.target_site_slug` should match `omeka.site_slug` |
| Sample item copy | **`config/omeka-test/sample-from-prod.yaml`** | Points at `local.settings` for API identity |

PHP entrypoints read **`/config/settings.yaml`** (Compose bind-mount). **`omeka.site_slug`** drives site creation ([`ensure-omeka-test-site.php`](../scripts/php/ensure-omeka-test-site.php)).

## Cross-repo alignment (manual)

| Field | Test stack SSOT | Archiver uploader SSOT |
|-------|-----------------|-------------------------|
| Site slug | `settings.yaml` → `omeka.site_slug` | [`hitsave-archiver` `config/omeka-uploader.yaml`](https://github.com/hitsave/hitsave-archiver/blob/main/config/omeka-uploader.yaml) → `api.site_slug` |
| Item set title | `omeka.item_set_title` | `api.item_set_title` |
| API base (from Docker on host) | `api.base_url` (`host.docker.internal:8088`) | same file |
| Credentials | Private **hitsave-archiver-config** → `secrets/omeka-api-credentials-local.yaml` | mounted at `/config/secrets/` in archiver Compose |

Preservation paths and ingest limits live in **hitsave-archiver** — see [config-contract.md there](https://github.com/hitsave/hitsave-archiver/blob/main/docs/config-contract.md).

## Intentional duplication

| Copy | SSOT | Notes |
|------|------|--------|
| Compose publish port `8088:8080` | `settings.yaml` → `omeka.public_url` | Port in URL must match compose publish |
| `omeka-prod-source.yaml` `mirror.target_site_slug` | `omeka.site_slug` | Mirror scripts do not auto-read settings; keep equal when you rename the test site |
| Legacy `config/omeka-test/omeka-api.yaml` | **`settings.yaml` `api:`** | Deprecated; [`omeka_settings.py`](../scripts/omeka_settings.py) falls back if present |

## Anti-patterns

- Hardcoding `hitsave-test` or `8088` in new scripts — read `settings.yaml` (see [`omeka_settings.py`](../scripts/omeka_settings.py) or `sync-docker-config.py`).
- Duplicating API blocks in `sample-from-prod.yaml` — use `local.settings`.
- Storing admin passwords in committed YAML — only in gitignored `settings.yaml`.

See also: [build-real-dip.md](./build-real-dip.md), [omeka-production.md](./omeka-production.md).
