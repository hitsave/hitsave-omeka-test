# Omeka production and test: DIP viewer, ARKs, visibility

This document captures how [archive.hitsave.org](https://archive.hitsave.org) is set up today, how the **OmekaDipViewer** ingest path should behave on prod, and how the local **hitsave-omeka-test** stack differs. It complements this repo’s [README.md](../README.md) and **hitsave-archiver** preservation docs.

## Production vs test

| | Production | Test (this repo) |
|---|------------|----------------------|
| URL | https://archive.hitsave.org | `config/omeka-test/settings.yaml` → `omeka.public_url` (e.g. `http://127.0.0.1:8088`) |
| Site slug | `start` | `hitsave-test` (configurable) |
| DIP browse | Legacy: many native media + LightGallery; **target:** one DIP `.tar` per game via **OmekaDipViewer** | OmekaDipViewer only |
| ARKs | **Ark** module active | **Common + Ark** in test image (Ark 3.5.17; prod 3.5.15), NAAN **78322**, internal ids; resolver URL **`/s/{site_slug}/ark:/…`** (prod serves **`/ark:/…`** at host root) |
| Archivematica Connector | Was used historically; **not** required for DipViewer | Removed from Docker image and install scripts |

Theme/nav/template for test can be mirrored from prod with `scripts/pull-omeka-prod-mirror.py` and `scripts/apply-omeka-prod-mirror.php` (output under gitignored `config/omeka-test/mirror/`; copy `omeka-prod-source.yaml.example` first).

---

## Persistent identifiers (ARKs)

Hit Save! documents ARKs on the public [Identifiers](https://archive.hitsave.org/s/start/page/identifiers) site page (`ark:` prefix → [arks.org](https://arks.org)).

### Module stack on production

Verified via production API (read-only):

- **[Ark](https://gitlab.com/Daniel-KM/Omeka-S-module-Ark)** (Daniel Berthereau) — **v3.5.15**, active. Creates and resolves ARKs; stores values in metadata; registers `/ark:/…` routes.
- **[Common](https://gitlab.com/Daniel-KM/Omeka-S-module-Common)** — required by Ark (minimum version enforced at Ark install).
- **[Clean Url](https://gitlab.com/Daniel-KM/omeka-s-module-CleanUrl)** — active; optional SEO/clean URLs (often used alongside ARKs).

Ark module settings are **not** exposed through the Omeka REST API. Configure in **Admin → Modules → Ark → Configure**, or inspect `omeka_settings` / module config on the server if needed.

### Internal names only (NOID not used)

We **do not** use the Ark module’s **NOID** name generator or NOID storage backend (`files/arkandnoid`, LMDB/XML templates, check digits, etc.). NOID was attempted early on but never worked reliably in our environment, so production standardised on **internal resource ids**.

In Ark settings this corresponds to:

- **Name processor for resource:** **Internal resource id** (`ark_name` = `internal`), **not** Noid.
- **NAAN:** **78322** (Hit Save! assigning authority).
- **Property:** **`dcterms:identifier`** (`ark_property`).

### Identifier format in production

| Resource | Example | Notes |
|----------|---------|--------|
| Item | `ark:/78322/9677` | Name segment = Omeka `o:id` |
| Item set | `ark:/78322/1459` | e.g. Press and Marketing Materials |
| Media (native, legacy) | `ark:/78322/9677/9678` | One **component** level: Omeka media id under item **9677** |
| DIP file (target) | `ark:/78322/6282/198/f1` | **Component path** under item Name **6282** (see below) |
| DIP derivative (target) | `ark:/78322/6282/198/f1.access` | **Variant path** after the file component (thumbnail, stream, etc.) |

Items expose the ARK in **`dcterms:identifier`** (literal). The public NAAN policy page is served at [https://archive.hitsave.org/ark:/78322](https://archive.hitsave.org/ark:/78322).

### ARK qualifier design (hierarchy + variants)

Hit Save follows [ARK Alliance identifier concepts](https://arks.org/about/identifier-concepts-and-conventions/): after **NAAN/Name**, optional **qualifiers** are **service entry points** the NMA (`archive.hitsave.org`) interprets—not a second minted Name.

We use two qualifier mechanisms from the ARK spec ([ARK spec](https://arks.org/assets/documents/2024/ark_spec_39.pdf)):

| Mechanism | Separator | Use on Hit Save |
|-----------|-----------|-----------------|
| **Component path** | `/` | Containment: item → DIP package (media) → logical file inside the tar |
| **Variant path** | `.` | Same logical file, different delivery: original bytes vs thumbnail vs streaming access copy |

**Name** is always the Omeka **item** `o:id` (the game / accession record). **Do not** mint separate Names for DIP files.

**Canonical examples** (classic spelling; modern `ark:78322/6282/198/f1` is equivalent):

| Intent | ARK | Resolves to (target behaviour) |
|--------|-----|----------------------------------|
| Cite the game | `ark:/78322/6282` | Item show page |
| Cite a file inside the DIP | `ark:/78322/6282/198/f1` | OmekaDipViewer file **f1** on DIP media **198** (same bytes as `/omeka-dip/file/198/f1`) |
| Stream / access copy | `ark:/78322/6282/198/f1.access` | Same as `?variant=access` today |
| Thumbnail (when exposed) | `ark:/78322/6282/198/f1.thumbnail` | Derived preview, not a new component |

**Component path rules:**

- Segment **`{dip_media_id}`** = Omeka media row holding the `.tar` DIP (`omeka_dip_package`).
- Segment **`{file_key}`** = stable key from the DIP index (METS/object path), same as in `/omeka-dip/file/{media_id}/{file_key}`.
- **Legacy native media** (pre–DipViewer expansion) keeps a **single** component: `ark:/78322/{item_id}/{media_id}`.

**Variant path rules:**

- Variants are **suffixes** on the deepest component, joined with `.` (not extra `/` levels).
- Names are **operational**, not reassigned by NAAN: `access`, `thumbnail`, and future derivatives (e.g. `poster`) must be documented on the Identifiers / NAAN policy page once exposed.
- Prefer ARK variants over query strings for citable links to derivatives (`?variant=access` remains a valid HTTP shortcut until ARK resolution is implemented).

**What we do not do:**

- Mint a new ARK Name per file inside a DIP (would fragment identity away from the item).
- Encode thumbnails or transcodes as extra `/` components (those are **variants** of the same file component).

**Implementation status:** **OmekaDipViewer 0.3.20+** registers a site route for the DIP **component path** (alongside Daniel-KM **Ark**):

`{public_url}/s/{site_slug}/ark:/78322/{item_id}/{dip_media_id}/{file_key}[.{variant}]`

Example (test stack): `http://127.0.0.1:8088/s/hitsave-test/ark:/78322/201/202/f0` → `screenshot.jpg` bytes (same as `/omeka-dip/file/202/f0`). Variants use the ARK variant suffix, e.g. `…/f2.access` for a streaming copy.

Production still serves **`/ark:/…`** at the host root; test uses the **`/s/{site_slug}/ark:`** prefix until root routing matches prod. Item and single-segment media ARKs remain the Ark module; in-tar files use the **four-segment** path above (not a second minted Name).

### Resolution

- **Local NMA:** `https://archive.hitsave.org/ark:/78322/{name}` → item (or item set) show page; extended qualifiers → item page, file stream, or redirect (when implemented).
- **Global resolver:** `https://n2t.net/ark:/78322/{name}` redirects through [arks.org](https://arks.org) to `archive.hitsave.org` (verified for sample items). Full qualifier strings must be forwarded unchanged to the NMA.

### When ARKs are assigned

The Ark module hooks **`api.create.post`** and **`api.update.post`** on items, media, and item sets. If **`dcterms:identifier`** does not already contain an ARK, the module mints one (`addArk` in Ark `Module.php`). It **does not** overwrite an existing ARK.

Implications for **agent ingest** (`scripts/upload-dip-omeka-api.py`):

- **Do not** POST `dcterms:identifier` with `ark:/78322/…` from the uploader—the item id is not known until after create, and the module should mint the ARK on prod.
- After a successful **`POST /api/items`** on production (with Ark active), expect `dcterms:identifier` = `ark:/78322/{new_item_id}` on read-back.

### DIP + ARK checklist for production cutover

1. Install **Common + Ark** on any new environment that must behave like prod (test mirror optional but recommended).
2. Match prod: NAAN **78322**, name processor **internal**, property **`dcterms:identifier`**.
3. Confirm n2t / NAAN registration still points at `archive.hitsave.org`.
4. One DIP item per game → one ARK; verify `https://archive.hitsave.org/ark:/78322/{id}` after ingest.
5. Document DIP **component** + **variant** qualifiers on the public Identifiers page when resolver support ships; keep HTTP `/omeka-dip/file/{media_id}/{file_key}` as the operational URL until then.
6. Implement qualifier resolution: `/{dip_media_id}/{file_key}[.{variant}]` → DipViewer with item-level visibility (see visibility section).

---

## Item and media visibility (production policy)

Omeka S stores **`o:is_public` separately** on each item and each media record. There is no core “media always inherits item” flag.

### Intended policy

- **Default:** new ingest items are **private** (`config/omeka-test/settings.yaml` → `api.default_is_public: false`; archiver uploader: `config/omeka-uploader.yaml`; same intent on prod for agent uploads).
- **Visibility is controlled at the item level.** Catalogers should not need a separate “hide this DIP media” step when the whole item is draft or published.
- When an item is **published**, its DIP **media** should be **public** as well so the site carousel, file tree, and `/omeka-dip/file/…` streams work for anonymous users.

### What ingest does today

`scripts/upload-dip-omeka-api.py` sets the **same** `o:is_public` on the item and the nested DIP media in one multipart create (see `create_item_with_dip`).

### Gaps to close before / during prod DIP rollout

1. **Admin “Make public” on an item** does not automatically update all media. A listener in OmekaDipViewer (or ops procedure) should sync DIP media `o:is_public` when the item changes.
2. **OmekaDipViewer** `DipFileController` currently checks **`$media->isPublic()`** for anonymous access. If the item is public but media was left private, streams return 404 even though the item exists—align controller logic with item read access or enforce sync on publish.

---

## OmekaDipViewer (DIP browse)

- **Module:** [`omeka-dip-viewer`](https://github.com/hitsave/omeka-dip-viewer) → `modules/OmekaDipViewer`; ingester **“DIP package (browse in place)”** (`omeka_dip_package` renderer).
- **Does not depend** on Archivematica Connector; METS-in-`.tar` parsing is internal.
- **Site layout:** carousel/video full width; package file tree moved to the right column beside metadata (`dip-layout.js` + theme `mediaList` in `full_width_main` / `main` / `right`).
- **Module upgrades:** bump `config/module.ini` version and run `scripts/ensure-omeka-dip-viewer-upgrade.php` after code changes (syncs DB version, clears opcache, deactivates removed modules such as legacy HitSaveDipViewer / Connector if still marked active in MariaDB).

Production **resource page blocks** (present in local mirror output `config/omeka-test/mirror/prod-archive.yaml` after a prod pull):

- `full_width_main`: `mediaList`
- `main`: `values`, `itemSets`
- `right`: `mediaList` (DipViewer renders DIP once in full width; second block skipped via custom `mediaList` layout)

---

## Ingest configuration references

| File | Purpose |
|------|---------|
| `config/omeka-test/settings.yaml` | SSOT for test stack; `api:` block for REST tools (see [config-contract.md](./config-contract.md)) |
| `config/omeka-test/omeka-prod-source.yaml` | Read-only prod mirror source (copy from `omeka-prod-source.yaml.example`; gitignored) |
| hitsave-archiver `config/omeka-uploader.yaml` | omeka-uploader container (keep aligned with test `settings.yaml` `api:` / `omeka:`) |
| hitsave-archiver `config/preservation/ingest.yaml` | Worker / ledger; not Omeka-specific |

Press and Marketing Materials item set: prod **`o:id` 1459**; test stack resolves by title from `settings.yaml` (`omeka.item_set_title` / `api.item_set_title`).

---

## Related scripts

| Script | Role |
|--------|------|
| `scripts/run-omeka-test.sh` | Build/start test Omeka, install/upgrade OmekaDipViewer |
| `scripts/ensure-omeka-dip-viewer-upgrade.php` | DB version sync + orphan module cleanup |
| `scripts/apply-omeka-prod-mirror.php` | Apply mirrored pages/theme; **replaces** pages by slug (avoids duplicate blocks on re-run) |
| `scripts/pull-omeka-prod-mirror.py` | Pull site/pages/template from prod API into gitignored `config/omeka-test/mirror/` |

---

## Archivematica Connector (deprecated for this path)

**OmekaDipViewer** replaces “expand DIP into hundreds of native media rows” for new press ingest. The upstream **ArchivematicaConnector** Omeka module is **not** installed in the test Docker image and is **not** a dependency of DipViewer. New ingest uses **E-ARK DIP** `.tar` packages from `scripts/build-dip-e-ark.py` (CSIP METS + representations); only the **Omeka import** path changed.

Optional research on full Archivematica + Connector import remains in `plan.md` §14 (deferred).
