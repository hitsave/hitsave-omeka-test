# hitsave-omeka-test

Local **Omeka S** stack for HitSave archive QA: **HitSaveArchive** theme, **OmekaDipViewer**, prod mirror scripts, and fixture DIPs. Preservation ingest and REST upload live in sibling [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver).

## Layout

```text
~/hitsave-archiver/           # Postgres ledger, ingest worker, omeka-uploader
~/hitsave-archiver-config/    # secrets (private)
~/hitsave-omeka-test/         # this repo — MariaDB + Omeka on :8088
```

Override paths with `HITSAVE_ARCHIVER_ROOT` and `HITSAVE_PRIVATE_CONFIG` when clones are not siblings.

## Quick start

```bash
git clone https://github.com/hitsave/hitsave-omeka-test.git
cd hitsave-omeka-test

./scripts/ensure-local-config.sh   # settings.yaml from example
./scripts/shell/run-omeka-test.sh  # build image, start stack, enable modules
```

Admin URL and password: `config/omeka-test/settings.yaml` (`omeka.public_url`, `omeka.admin_password`).

Build fixture DIPs (requires a **hitsave-archiver** clone):

```bash
./scripts/shell/build-fixture-dips.sh
./scripts/shell/create-dip-example-item.sh /fixtures/dips/built/sample-game.tar
```

End-to-end ingest from press material uses **archiver** `game.yml` plus:

```bash
./scripts/shell/create-dip-from-press-pilot.sh
```

## Prod mirror

Copy `config/omeka-test/omeka-prod-source.yaml.example` → `omeka-prod-source.yaml` (gitignored), fill read-only API credentials from **hitsave-archiver-config**, then:

```bash
./scripts/shell/sync-omeka-prod-mirror.sh
```

## DIP output mount

Compose mounts `${DIP_OUTPUT_ROOT:-/tank/hitsave-archiver/output}/dip` read-only at `/dip-output` inside Omeka for attaching preservation tars.

## Docs

- [docs/omeka-production.md](docs/omeka-production.md) — production vs test, ARKs, visibility
- [docs/archive-theme-1plus4.md](docs/archive-theme-1plus4.md) — theme layout notes

## Related repos

| Repo | Role |
|------|------|
| [hitsave-archiver](https://github.com/hitsave/hitsave-archiver) | E-ARK ingest, Omeka REST uploader |
| [omeka-dip-viewer](https://github.com/hitsave/omeka-dip-viewer) | DIP browse module (baked into Omeka image) |
| [hitsave-archive-theme](https://github.com/hitsave/hitsave-archive-theme) | Foundation overlay theme |
