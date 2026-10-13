# hitsave-omeka-test

Local **Omeka S** stack for HitSave archive QA: **HitSaveArchive** theme, **OmekaDipViewer**, and prod mirror scripts.

**Ingest and DIP catalog registration** run only from [**hitsave-archiver**](https://github.com/hitsave/hitsave-archiver) (`docker compose` + **omeka-catalog**). This repo is the Omeka sidecar on `:8088`.

## Layout

```text
~/hitsave-archiver/           # run ingest + Omeka catalog register (omeka-catalog) here; *.example templates live here
~/hitsave-archiver-config/    # your secrets (copy from archiver examples — see operator-config.md)
~/hitsave-omeka-test/         # this repo; config/omeka-test/*.example for Omeka admin/DB
```

## Quick start

```bash
git clone https://github.com/hitsave/hitsave-omeka-test.git
cd hitsave-omeka-test
./scripts/ensure-local-config.sh
./scripts/shell/run-omeka-test.sh
```

End-to-end DIP QA (archiver ingest + uploader, then browse in this Omeka): **[docs/build-real-dip.md](docs/build-real-dip.md)**.

## Prod mirror

Copy `config/omeka-test/omeka-prod-source.yaml.example` → `omeka-prod-source.yaml` (gitignored), fill read-only API credentials from **hitsave-archiver-config**, then:

```bash
./scripts/shell/sync-omeka-prod-mirror.sh
```

## Docs

- [docs/config-contract.md](docs/config-contract.md) — which YAML owns what (SSOT)
- [docs/build-real-dip.md](docs/build-real-dip.md) — archiver ingest + Omeka catalog register (omeka-catalog)
- [docs/dip-wasabi-s3-direct.md](docs/dip-wasabi-s3-direct.md) — Wasabi S3 for OmekaDipViewer
- [docs/omeka-production.md](docs/omeka-production.md) — production vs test, ARKs, visibility
- [docs/archive-theme-1plus4.md](docs/archive-theme-1plus4.md) — theme layout notes

## Related repos

| Repo | Role |
|------|------|
| [hitsave-archiver](https://github.com/hitsave/hitsave-archiver) | BagIt ingest, Omeka catalog registration |
| [omeka-dip-viewer](https://github.com/hitsave/omeka-dip-viewer) | DIP browse module (baked into Omeka image) |
| [hitsave-archive-theme](https://github.com/hitsave/hitsave-archive-theme) | Foundation overlay theme |
