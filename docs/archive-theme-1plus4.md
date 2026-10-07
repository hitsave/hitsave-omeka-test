# Hit Save archive theme — discovery hub + family chrome (1+4)

This document specifies the **HitSaveArchive** Omeka S theme: a Foundation overlay for [archive.hitsave.org](https://archive.hitsave.org) and the local test site.

## Goals

| Track | Intent |
|-------|--------|
| **1 — Discovery hub** | Homepage orients visitors: search, thematic entry points, featured/recent material. |
| **4 — Family chrome** | Header/footer align with [hitsave.org](https://hitsave.org) and [preserve.games](https://preserve.games); archive reads as “the vault.” |

Production today uses **Foundation** with homepage **`intro`**, nav to press material, and support links (see local mirror output after `pull-omeka-prod-mirror.py`). This theme keeps those Omeka settings and adds shared chrome + item citation UX.

## Information architecture

```text
┌─────────────────────────────────────────────────────────────┐
│ Family bar: Hit Save! | Preserve Games | The Archive (here) │
├─────────────────────────────────────────────────────────────┤
│ Site title + Omeka nav (dropdown) + search                  │
├─────────────────────────────────────────────────────────────┤
│ [Homepage only] Hero + search                               │
│ Collection tiles (Press, Magazines, VHS, …)                 │
│ Featured / recent row (optional HTML or browse block)       │
├─────────────────────────────────────────────────────────────┤
│ Main content (pages, items, browse)                         │
├─────────────────────────────────────────────────────────────┤
│ Mission footer (theme setting) + family links + donate      │
└─────────────────────────────────────────────────────────────┘
```

Item pages keep Foundation **resource page blocks** (prod: `mediaList` full width + values/itemSets). Add **Cite this record** when `dcterms:identifier` contains an ARK.

## Omeka configuration

### Theme

- **Name:** `HitSaveArchive` (open-source **Foundation S** fork + overlay; pin in `themes/hitsave-archive-overlay/FOUNDATION_S_GIT_REF`).
- **Docs / license:** [themes/hitsave-archive-overlay/README.md](../themes/hitsave-archive-overlay/README.md), [COPYING.md](../themes/hitsave-archive-overlay/COPYING.md).
- **Build:** `scripts/build-hitsave-archive-theme.sh` during `omeka-test` image build (`FOUNDATION_S_GIT_REF` → Docker clone tag).
- **Upstream checks:** `./scripts/check-foundation-theme-upstream.sh` when Foundation S releases.
- **Test mirror:** `config/omeka-test/omeka-prod-source.yaml` → `mirror.target_theme: HitSaveArchive`.

Family URL defaults live in `config/archive-theme.yml` and theme settings (`hitsave_org_url`, etc.).

### Homepage recipe (`intro` or replacement page)

Use site page blocks (no custom module required):

1. **HTML — hero**  
   - H1: site title or “Hit Save! Archive”  
   - Short line on video game preservation  
   - Link to site search: `/s/{slug}/item` or the search form anchor  

2. **Browse preview or HTML — collection tiles**  
   Markup pattern (classes styled in `hitsave-archive.css`):

   ```html
   <div class="hitsave-tiles grid-x grid-margin-x small-up-1 medium-up-2 large-up-3">
     <a class="hitsave-tile cell" href="/s/start/page/press-material">
       <span class="hitsave-tile__label">Press &amp; marketing</span>
       <span class="hitsave-tile__hint">Flyers, ads, pack-in art</span>
     </a>
     <!-- more tiles: magazines, VHS, software, … -->
   </div>
   ```

3. **Optional:** Item with media block or “recent items” browse for a carousel row.

Replace `start` with `hitsave-test` on the test stack.

### Navigation (mirror prod)

Keep external links first (get involved, support), then in-site pages (press material), then filtered browse (e.g. VHS fulltext search).

### Theme settings (site admin → Theme)

| Setting | Prod-oriented value |
|---------|---------------------|
| `nav_layout` | `dropdown` |
| `footer` | Non-profit mission line (see mirror YAML) |
| `hitsave_*` URLs | From `config/archive-theme.yml` |

### Item “Cite this record”

When Ark/Common writes `dcterms:identifier` as `ark:/78322/…`, the theme shows:

- Persistent ARK string  
- Permalink to the item page  
- Suggested citation line (title + Hit Save! Archive + ARK)

DIP file URLs remain module responsibility (`OmekaDipViewer` + ARK route); do not link `/omeka-dip/file/…` in public theme when ARK is active.

## CSS tokens

Palette tracks **hitsave.org** Ghost theme (teal-forward, multi-color — not brown/gold):

- Teal: `#00BEC1` (primary buttons/links)
- Purple: `#6d327c`, green: `#32b37b` (hub gradient + tile accents)
- Page gray: `#F4F4F4`, chrome/footer: `#222228` / `#1c1c22`
- Footer top: purple → teal → green stripe

See `themes/hitsave-archive-overlay/asset/css/hitsave-archive.css` and `config/archive-theme.yml`.

## Production cutover (later)

1. Build/publish Omeka image or rsync `HitSaveArchive` theme to prod volume.  
2. Switch site `start` theme to `HitSaveArchive`; re-apply theme settings from mirror.  
3. Refresh homepage blocks per recipe above.  
4. **Root ARK URLs** (`/ark:/78322/…` without `/s/start/`) still depend on Clean URL / routing on prod — separate from this theme.

## References

- V&A Explore, Cooper Hewitt collection, Digital Commonwealth — collection-first hubs.  
- Omeka peers: Nebraskaland, Library Theme — block-based homepages on Foundation-like layouts.
