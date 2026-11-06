#!/usr/bin/env bash
# Deploy the HitSaveArchive theme to production Omeka on mario.
#
# Runs every remote step through the hitsave tailnet container on this host (hitsave-ts,
# hitsave-archiver-config/hosts/saturn/tailscale/), so the host itself never joins the tailnet.
# Same layout and conventions as deploy-omeka-dip-viewer-mario.sh.
#
#   deploy-hitsave-archive-theme-mario.sh BUILT_THEME_DIR        # deploy a built theme (see below)
#   deploy-hitsave-archive-theme-mario.sh --diff BUILT_THEME_DIR # read-only: files that would change
#   deploy-hitsave-archive-theme-mario.sh --preflight            # read-only checks only
#   deploy-hitsave-archive-theme-mario.sh --rollback BACKUP.tar.gz   # restore a backup (copy it from
#                                                                    # $STACK/backups first)
#
# BUILT_THEME_DIR is the output of hitsave-archive-theme's build (Foundation + HitSave overlay):
#   ./scripts/build-hitsave-archive-theme.sh ./foundation-theme /tmp/build/HitSaveArchive .
# Run --diff first: production may carry fixes that were never built from git.
#
# A .git directory in the live theme dir (it doubles as a git working tree on mario) is carried over
# into the new directory and ignored by --diff.
#
# Steps: preflight (host, container, current theme version) -> back up the live theme directory to
# $STACK/backups -> pre-check every .php/.phtml on the target's own PHP -> swap the directory (old
# kept as .deploying until VERIFY_URL answers 200, else restored) -> verify the site and the page's
# Open Graph tags. No restart: production's OPcache revalidates file timestamps every 2s. Themes have
# no database version, so there is no upgrade step.
#
# Production layout (2026-11): Komodo stack from hitsave/docker-inventory (mario/omeka), container
# "omeka", /opt/stacks/omeka/volume bind-mounted at /var/www/html/volume (themes live on the host).
# MARIO_HOST=local rehearses on this machine (e.g. MARIO_OMEKA_CONTAINER=hitsave-omeka-test-omeka-1
# MARIO_OMEKA_STACK=/path/to/hitsave-omeka-test VERIFY_URL=http://localhost:8088/s/hitsave-test).
set -euo pipefail

MARIO="${MARIO_HOST:-mario}"
SSH_USER="${MARIO_SSH_USER:-root}"
STACK="${MARIO_OMEKA_STACK:-/opt/stacks/omeka}"          # backups go to $STACK/backups
OMEKA_CONTAINER="${MARIO_OMEKA_CONTAINER:-omeka}"
TS_CONTAINER="${HITSAVE_TS_CONTAINER:-hitsave-ts}"
SSH_KEY="${MARIO_SSH_KEY:-}"           # empty = Tailscale SSH (tailnet identity, no key)
VERIFY_URL="${VERIFY_URL:-https://archive.hitsave.org/ark:/78322/27722}"
THEME="${THEME_ID:-HitSaveArchive}"
THEME_DIR_IN_CONTAINER="/var/www/html/volume/themes/$THEME"

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ "$MARIO" != local ]]; then
  docker inspect -f '{{.State.Running}}' "$TS_CONTAINER" 2>/dev/null | grep -q true \
    || die "$TS_CONTAINER is not running (hitsave-archiver-config/hosts/saturn/tailscale/compose.yaml)"
fi

# ssh/scp in a throwaway container sharing the tailnet namespace (it inherits MagicDNS; Docker
# rejects --dns together with --network container:).
remote() {
  local key_mount=()
  if [[ -n "$SSH_KEY" ]]; then key_mount=(-v "$SSH_KEY:/k:ro"); fi
  docker run --rm -i --network "container:$TS_CONTAINER" "${key_mount[@]}" \
    -v "${WORK:-/tmp}:/work:ro" alpine:3.20 sh -c \
    "apk add -q --no-cache openssh-client >/dev/null && $*" ;
}
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 ${SSH_KEY:+-i /k}"
run_ssh() {
  if [[ "$MARIO" == local ]]; then bash -s; else remote "ssh $SSH_OPTS ${SSH_USER}@${MARIO} 'bash -s'"; fi
}
push_file() {   # $1 = local file, $2 = remote path
  if [[ "$MARIO" == local ]]; then cp "$1" "$2"; else
    WORK="$(dirname "$1")" remote "scp $SSH_OPTS /work/$(basename "$1") ${SSH_USER}@${MARIO}:$2"; fi
}

preflight() {
  run_ssh <<REMOTE
set -euo pipefail
echo "host: \$(hostname)"
OID="$OMEKA_CONTAINER"
docker ps --filter "name=^\$OID\$" --format '{{.Names}} {{.Image}} {{.Status}}' | grep .
docker exec "\$OID" sh -c 'grep -m1 "^version" $THEME_DIR_IN_CONTAINER/config/theme.ini'
df -h "$STACK" | tail -1
REMOTE
}

# sha256 listing of a theme tree, relative paths (sorted): used by --diff on both sides.
LIST_CMD='find . -path ./.git -prune -o -type f ! -name ".DS_Store" -print0 | sort -z | xargs -0 sha256sum'

diff_against_live() {   # $1 = local tarball of the built theme
  local tarball="$1"
  push_file "$tarball" /tmp/hitsave-theme-diff.tar.gz
  run_ssh <<REMOTE
set -euo pipefail
OID="$OMEKA_CONTAINER"
rm -rf /tmp/htd && mkdir -p /tmp/htd && tar -xzf /tmp/hitsave-theme-diff.tar.gz -C /tmp/htd
(cd /tmp/htd/$THEME && $LIST_CMD) > /tmp/htd/new.txt
docker exec "\$OID" sh -c 'cd $THEME_DIR_IN_CONTAINER && $LIST_CMD' > /tmp/htd/live.txt
echo "--- changed or only in the build (would be deployed):"
diff <(sort -k2 /tmp/htd/live.txt) <(sort -k2 /tmp/htd/new.txt) | grep '^>' | awk '{print "  " \$3}' || true
echo "--- only on production (would be REMOVED by a deploy):"
join -1 2 -2 2 -v 1 <(sort -k2 /tmp/htd/live.txt) <(sort -k2 /tmp/htd/new.txt) | awk '{print "  " \$1}' || true
rm -rf /tmp/htd /tmp/hitsave-theme-diff.tar.gz
REMOTE
}

install_tarball() {   # $1 = tarball path, $2 = label
  local tarball="$1" label="$2"
  push_file "$tarball" /tmp/hitsave-theme-deploy.tar.gz
  run_ssh <<REMOTE
set -euo pipefail
OID="$OMEKA_CONTAINER"
docker ps --filter "name=^\$OID\$" -q | grep -q .
TS="\$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$STACK/backups"
OLD="\$(docker exec "\$OID" sh -c 'grep -m1 "^version" $THEME_DIR_IN_CONTAINER/config/theme.ini | cut -d\\" -f2')"
BACKUP="$STACK/backups/$THEME-\${OLD}-\${TS}.tar.gz"
docker exec "\$OID" tar -C /var/www/html/volume/themes -czf - $THEME > "\$BACKUP"
echo "backup: \$BACKUP (\$(du -h "\$BACKUP" | cut -f1))"
rm -rf /tmp/hst-new && mkdir -p /tmp/hst-new && tar -xzf /tmp/hitsave-theme-deploy.tar.gz -C /tmp/hst-new
test -f /tmp/hst-new/$THEME/config/theme.ini
# Pre-check on the target's own PHP BEFORE touching the live theme: lint every .php/.phtml.
docker exec -u 0 "\$OID" rm -rf /tmp/hst-stage
docker cp /tmp/hst-new/$THEME "\$OID:/tmp/hst-stage"
LINT="\$(docker exec "\$OID" sh -c 'find /tmp/hst-stage \( -name "*.php" -o -name "*.phtml" \) -exec php -l {} \; 2>&1 | grep -v "^No syntax errors"' || true)"
docker exec -u 0 "\$OID" rm -rf /tmp/hst-stage
if [ -n "\$LINT" ]; then echo "pre-check failed (php -l):" >&2; echo "\$LINT" >&2; exit 1; fi
echo "pre-check: \$(docker exec "\$OID" php -r 'echo PHP_VERSION;') lint ok"
OWNER="\$(docker exec "\$OID" stat -c %u:%g $THEME_DIR_IN_CONTAINER)"
docker exec -u 0 "\$OID" sh -c 'rm -rf ${THEME_DIR_IN_CONTAINER}.deploying && mv $THEME_DIR_IN_CONTAINER ${THEME_DIR_IN_CONTAINER}.deploying'
docker cp /tmp/hst-new/$THEME "\$OID:$THEME_DIR_IN_CONTAINER"
# Production's theme dir is also a git working tree (hitsave-archive-theme README): keep its .git.
docker exec -u 0 "\$OID" sh -c 'if [ -d ${THEME_DIR_IN_CONTAINER}.deploying/.git ]; then rm -rf $THEME_DIR_IN_CONTAINER/.git && cp -a ${THEME_DIR_IN_CONTAINER}.deploying/.git $THEME_DIR_IN_CONTAINER/.git; fi'
docker exec -u 0 "\$OID" chown -R "\$OWNER" $THEME_DIR_IN_CONTAINER
rm -rf /tmp/hst-new /tmp/hitsave-theme-deploy.tar.gz
sleep 3   # OPcache revalidate_freq=2: new files are live after this
echo "$label: swapped (previous theme kept as ${THEME_DIR_IN_CONTAINER}.deploying until verified)"
REMOTE
}

# After the swap: keep the new theme only if VERIFY_URL answers 200 from here; else put the old one back.
settle() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$VERIFY_URL" || true)"
  echo "check $VERIFY_URL -> HTTP $code"
  if [[ "$code" == 200 ]]; then
    run_ssh <<REMOTE
docker exec -u 0 "$OMEKA_CONTAINER" rm -rf ${THEME_DIR_IN_CONTAINER}.deploying
REMOTE
  else
    run_ssh <<REMOTE
set -euo pipefail
docker exec -u 0 "$OMEKA_CONTAINER" sh -c 'rm -rf $THEME_DIR_IN_CONTAINER && mv ${THEME_DIR_IN_CONTAINER}.deploying $THEME_DIR_IN_CONTAINER'
REMOTE
    die "site did not answer 200 after the swap; previous theme restored"
  fi
}

verify() {
  sleep 2
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$VERIFY_URL")"
  echo "verify $VERIFY_URL -> HTTP $code"
  [[ "$code" == 200 ]] || die "verify page did not return 200 (roll back with --rollback and the backup above)"
  if [[ "$MARIO" != local ]]; then
    curl -fsSL -A 'Discordbot (2.0; +https://discordapp.com)' "$VERIFY_URL" | grep -c 'property="og:' \
      | xargs -I{} echo "verify: {} og: tags"
  fi
  preflight
}

pack() {   # $1 = built theme dir -> prints tarball path
  local src
  src="$(realpath "$1")"
  [[ -f "$src/config/theme.ini" ]] || die "$src is not a built theme (needs config/theme.ini)"
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/$THEME"
  cp -a "$src/." "$WORK/$THEME/"
  rm -rf "$WORK/$THEME/.git"
  tar -C "$WORK" -czf "$WORK/hitsave-theme.tar.gz" "$THEME"
  echo "==> theme $(grep -m1 '^version' "$src/config/theme.ini") from $src" >&2
  PACKED="$WORK/hitsave-theme.tar.gz"
}

case "${1:-}" in
  --preflight) preflight ;;
  --diff)
    [[ -n "${2:-}" ]] || die "usage: $0 --diff BUILT_THEME_DIR"
    pack "$2"; diff_against_live "$PACKED" ;;
  --rollback)
    [[ -f "${2:-}" ]] || die "usage: $0 --rollback LOCAL_COPY_OF_BACKUP.tar.gz (copy it from $STACK/backups first)"
    install_tarball "$(realpath "$2")" "rollback"; settle; verify ;;
  ""|-h|--help) sed -n 2,27p "$0"; exit 0 ;;
  *)
    pack "$1"
    echo "==> preflight"; preflight
    install_tarball "$PACKED" "deploy"
    settle
    echo "==> verify"; verify ;;
esac
