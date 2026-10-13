# Wasabi S3 for OmekaDipViewer

Omeka reads **unpacked BagIt** packages from Wasabi with the **S3 API** (`DipS3ObjectStore`).

## Separate Omeka catalog bucket (recommended)

Keep **preservation / incoming** (`hitsave-incoming`: submissions, dumps, experiments) separate from **catalog DIP bytes** Omeka serves:

| Bucket | Typical prefixes | Writers | Readers |
|--------|------------------|---------|---------|
| `hitsave-dumps` | `dumps/` | ingest-worker (`wasabi.buckets.dumps`) | staff tools |
| `hitsave-press-material` | `press-material/` | ingest-worker (`wasabi.buckets.press_material`) | OmekaDipViewer |

Steps:

1. **Wasabi console** — create bucket in **us-east-2** (match `ingest.yaml` region), enable default encryption, block public access (Omeka uses API keys, not public ACLs).
2. **Access keys** — either extend the existing IAM user policy with `List/Get/Put` on the new bucket, or create `wasabi-omeka-read.yaml` (read-only for prod Omeka) plus writer key on the archiver host.
3. **Archiver** — in `hitsave-archiver/config/preservation/ingest.yaml` set `wasabi.buckets.press_material` and `wasabi.buckets.dumps` (required; no fallback bucket).
4. **Omeka** — separate **read-only** Wasabi user (see JSON policy in ops docs); do **not** reuse archiver ingest keys.
5. **Omeka config** — copy examples → local files, render PHP (below). Bucket name must match where press bags are uploaded (`wasabi.buckets.press_material` in archiver `ingest.yaml`).
6. **Re-ingest** — after bucket changes, reset ledger + re-upload so preflight hits the correct bucket.

## One-time setup (Omeka-only S3)

1. Copy and edit (both gitignored locally):

   - `config/omeka-test/dip-s3.yaml.example` → `dip-s3.yaml` (`bucket`, `endpoint`, `region`)
   - `config/omeka-test/dip-s3-credentials.yaml.example` → `dip-s3-credentials.yaml` (Omeka read-only keys)

2. Render module config:

```bash
cd hitsave-omeka-test
python3 scripts/shell/render-dip-s3-config.py
```

Optional args: `render-dip-s3-config.py [dip-s3.yaml] [output-dip-s3.config.php]`

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
| `dip_wasabi_uri` | `s3://hitsave-press-material/press-material/F/{package_id}/` |

DipViewer loads `metadata/inventory.json` and streams payload files from that prefix.

## Verify

```bash
docker compose exec omeka php /scripts/test-dip-media-index.php <media_id>
```

## Related

- [build-real-dip.md](./build-real-dip.md)
- [hitsave-archiver dip-wasabi-s3.md](https://github.com/hitsave/hitsave-archiver/blob/main/docs/dip-wasabi-s3.md)
