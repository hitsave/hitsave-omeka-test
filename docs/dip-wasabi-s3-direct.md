# Wasabi S3 for OmekaDipViewer

Omeka reads **unpacked BagIt** packages from Wasabi with the **S3 API** (`DipS3ObjectStore`).

## One-time setup

1. Copy Wasabi credentials into the test stack (same bucket as ingest: `hitsave-incoming`).

2. Render module config:

```bash
cd hitsave-omeka-test
python3 scripts/shell/render-dip-s3-config.py \
  --wasabi-credentials ../hitsave-archiver-config/secrets/wasabi-credentials.yaml \
  --output ../omeka-dip-viewer/config/dip-s3.config.php
```

Use the **regional** endpoint (e.g. `https://s3.us-east-2.wasabisys.com`).

3. Start Omeka with the S3 overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3-direct.yml up -d
```

`docker-compose.s3-direct.yml` bind-mounts `OmekaDipViewer` and `config/dip-s3.config.php`.

## Omeka media fields

After ingest and `register-dip-omeka-api.py`:

| Field | Example |
|-------|---------|
| `dip_storage` | `wasabi-s3` |
| `package_storage_prefix` | `press-material/F/{package_id}` |
| `dip_wasabi_uri` | `s3://hitsave-incoming/press-material/F/{package_id}/` |

DipViewer loads `metadata/inventory.json` and streams payload files from that prefix.

## Verify

```bash
docker compose exec omeka php /scripts/test-dip-media-index.php <media_id>
```

## Related

- [build-real-dip.md](./build-real-dip.md)
- [hitsave-archiver dip-wasabi-s3.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/dip-wasabi-s3.md)
