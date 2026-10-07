# hitsave-omeka-test

Local **Omeka S** stack for HitSave archive QA: **HitSaveArchive** theme, **OmekaDipViewer**, and prod mirror scripts. **E-ARK DIPs come from real preservation ingest** in sibling [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver), not from bundled fixture tars.

## Layout

```text
~/hitsave-archiver/           # Postgres ledger, ingest worker, omeka-uploader
~/hitsave-archiver-config/    # secrets (private)
~/hitsave-omeka-test/         # this repo — MariaDB + Omeka on :8088
```

Override paths with `HITSAVE_ARCHIVER_ROOT`, `HITSAVE_PRIVATE_CONFIG`, and `DIP_OUTPUT_ROOT` when clones or output paths differ.

## Quick start

```bash
git clone https://github.com/hitsave/hitsave-omeka-test.git
cd hitsave-omeka-test

./scripts/ensure-local-config.sh   # settings.yaml from example
./scripts/shell/run-omeka-test.sh  # build image, start stack, enable modules
```

Admin URL and password: `config/omeka-test/settings.yaml` (`omeka.public_url`, `omeka.admin_password`).

## Build a real DIP and attach it

Full walkthrough: **[docs/build-real-dip.md](docs/build-real-dip.md)**.

Short path (after `game.yml` exists in **hitsave-archiver**):

```bash
./scripts/shell/ingest-and-attach-dip.sh
```

Or ingest in archiver, then attach an existing tar from the output volume:

```bash
./scripts/shell/attach-dip-from-output.sh my-game.tar "My Game — press materials"
```

Compose mounts `${DIP_OUTPUT_ROOT:-/tank/hitsave-archiver/output}/dip` at `/dip-output` inside Omeka.

## Prod mirror

Copy `config/omeka-test/omeka-prod-source.yaml.example` → `omeka-prod-source.yaml` (gitignored), fill read-only API credentials from **hitsave-archiver-config**, then:

```bash
./scripts/shell/sync-omeka-prod-mirror.sh
```

## Docs

- [docs/build-real-dip.md](docs/build-real-dip.md) — press material → ingest → Omeka browse
- [docs/omeka-production.md](docs/omeka-production.md) — production vs test, ARKs, visibility
- [docs/archive-theme-1plus4.md](docs/archive-theme-1plus4.md) — theme layout notes

## Related repos

| Repo | Role |
|------|------|
| [hitsave-archiver](https://github.com/hitsave/hitsave-archiver) | E-ARK ingest, Omeka REST uploader |
| [omeka-dip-viewer](https://github.com/hitsave/omeka-dip-viewer) | DIP browse module (baked into Omeka image) |
| [hitsave-archive-theme](https://github.com/hitsave/hitsave-archive-theme) | Foundation overlay theme |
