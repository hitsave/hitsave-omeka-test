# Wasabi S3 direct access (OmekaDipViewer)

Omeka reads **unpacked BagIt** packages from Wasabi using the **S3 API** (`DipS3ObjectStore`). There is no rclone, FUSE, or `.tar` mount.

## One-time setup

1. Copy Wasabi credentials into the Omeka test stack (same bucket as ingest: `hitsave-incoming`).

2. Render module config from archiver secrets:

```bash
cd hitsave-omeka-test
python3 scripts/shell/render-dip-s3-config.py \
  --wasabi-credentials ../hitsave-archiver-config/secrets/wasabi-credentials.yaml \
  --output ../omeka-dip-viewer/config/dip-s3.config.php
```

Use the **regional** endpoint (e.g. `https://s3.us-east-2.wasabisys.com`), not the generic `s3.wasabisys.com` hostname.

3. Start Omeka with the S3 overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3-direct.yml up -d
```

`docker-compose.s3-direct.yml` bind-mounts `OmekaDipViewer` and `config/dip-s3.config.php`.

## Omeka media shape

After ingest + `upload-dip-omeka-api.py`, each press item has one **`omeka_dip_package`** media row with:

- `data.dip_storage`: `wasabi-s3`
- `data.package_storage_prefix`: e.g. `press-material/F/{package_id}`
- `data.dip_wasabi_uri`: `s3://hitsave-incoming/press-material/F/{package_id}/`

DipViewer loads `metadata/inventory.json` and streams payload bytes from that prefix.

## Verify

Inside the Omeka container (module enabled):

```bash
docker compose exec omeka php /scripts/test-dip-media-index.php <media_id>
```

Browse thumbnails and file streams should hit Wasabi without any `/hitsave-incoming` mount.

## Related

- Ingest + upload: [build-real-dip.md](./build-real-dip.md)
- Archiver Wasabi layout: [hitsave-archiver docs/dump-preservation.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/dump-preservation.md)
