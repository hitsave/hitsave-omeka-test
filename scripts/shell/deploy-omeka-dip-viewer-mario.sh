#!/usr/bin/env bash
# Deploy the OmekaDipViewer module to production Omeka on mario (/opt/stacks/hitsave-omeka).
#
# Runs every remote step through the hitsave tailnet container on this host (hitsave-ts,
# hitsave-archiver-config/hosts/saturn/tailscale/), so the host itself never joins the tailnet.
#
#   deploy-omeka-dip-viewer-mario.sh /path/to/omeka-dip-viewer            # deploy that checkout
#   deploy-omeka-dip-viewer-mario.sh --preflight                          # read-only checks only
#   deploy-omeka-dip-viewer-mario.sh --rollback BACKUP.tar.gz             # restore a backup on mario
#
# Steps: preflight (host, stack, current module version) -> back up the current module directory
# on mario -> upload and replace the module -> upgrade ONLY OmekaDipViewer through Omeka's module
# manager (records the new version; without it Omeka deactivates the module) -> verify the module
# is active at the expected version and the site serves. No restart: production's OPcache
# revalidates file timestamps every 2s (validate_timestamps=On, revalidate_freq=2).
#
# Production layout (2026-11-02): Komodo deploys the stack from hitsave/docker-inventory
# (mario/omeka/compose.yaml); container "omeka"; /opt/stacks/omeka/volume is bind-mounted at
# /var/www/html/volume, so the module lives on the host and survives container recreation. The
# script addresses the container by name and never runs docker compose (that would use a stale
# copy of the compose file and compete with Komodo).
set -euo pipefail

MARIO="${MARIO_HOST:-mario}"
SSH_USER="${MARIO_SSH_USER:-root}"
STACK="${MARIO_OMEKA_STACK:-/opt/stacks/omeka}"          # backups go to $STACK/backups
OMEKA_CONTAINER="${MARIO_OMEKA_CONTAINER:-omeka}"
TS_CONTAINER="${HITSAVE_TS_CONTAINER:-hitsave-ts}"
SSH_KEY="${MARIO_SSH_KEY:-}"           # empty = Tailscale SSH (tailnet identity, no key)
VERIFY_URL="${VERIFY_URL:-https://archive.hitsave.org/ark:/78322/27722}"
MODULE_DIR_IN_CONTAINER=/var/www/html/volume/modules/OmekaDipViewer

die() { echo "ERROR: $*" >&2; exit 1; }

# MARIO_HOST=local rehearses every remote step on this machine (e.g. against the local
# hitsave-omeka-test stack with MARIO_OMEKA_STACK=/path/to/hitsave-omeka-test and
# MARIO_OMEKA_CONTAINER=hitsave-omeka-test-omeka-1); no tailnet needed.
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
docker exec "\$OID" sh -c 'grep -m1 "^version" $MODULE_DIR_IN_CONTAINER/config/module.ini'
df -h "$STACK" | tail -1
REMOTE
}

UPGRADE_PHP='<?php
// Upgrade only OmekaDipViewer (records the new version; Omeka deactivates a module whose code is newer).
require "/var/www/html/bootstrap.php";
$app = Omeka\Mvc\Application::init(require OMEKA_PATH . "/application/config/application.config.php");
$sm = $app->getServiceManager();
// Module upgrades need an authenticated admin (CLI has none): act as the first global admin.
$admin = $sm->get("Omeka\\EntityManager")->getRepository(Omeka\Entity\User::class)->findOneBy(["role" => "global_admin", "isActive" => true]);
if (!$admin) { fwrite(STDERR, "no active global_admin user\n"); exit(1); }
$sm->get("Omeka\\AuthenticationService")->getStorage()->write($admin);
$mm = $sm->get("Omeka\\ModuleManager");
$m = $mm->getModule("OmekaDipViewer");
if (!$m) { fwrite(STDERR, "OmekaDipViewer not found\n"); exit(1); }
$before = $m->getState();
if ($before === "needs_upgrade") { $mm->upgrade($m); }
// Rollback: files older than the recorded version. Omeka has no downgrade, so record the version
// of the files (otherwise a startup hook or a later upgrade check sees a mismatch).
$em = $sm->get("Omeka\\EntityManager");
$row = $em->find(Omeka\Entity\Module::class, "OmekaDipViewer");
$ini = (string) $m->getIni("version");
if ($row && version_compare($row->getVersion(), $ini, ">")) { $row->setVersion($ini); $em->flush(); }
$m = $mm->getModule("OmekaDipViewer");
echo json_encode(["before" => $before, "after" => $m->getState(), "version" => $m->getIni("version")]), "\n";
exit($m->getState() === "active" ? 0 : 1);'

install_tarball() {   # $1 = tarball path inside /work, $2 = label
  local tarball="$1" label="$2"
  push_file "$tarball" /tmp/omeka-dip-viewer-deploy.tar.gz
  run_ssh <<REMOTE
set -euo pipefail
OID="$OMEKA_CONTAINER"
docker ps --filter "name=^\$OID\$" -q | grep -q .
TS="\$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$STACK/backups"
OLD="\$(docker exec "\$OID" sh -c 'grep -m1 "^version" $MODULE_DIR_IN_CONTAINER/config/module.ini | cut -d\\" -f2')"
BACKUP="$STACK/backups/OmekaDipViewer-\${OLD}-\${TS}.tar.gz"
docker exec "\$OID" tar -C /var/www/html/volume/modules -czf - OmekaDipViewer > "\$BACKUP"
echo "backup: \$BACKUP (\$(du -h "\$BACKUP" | cut -f1))"
rm -rf /tmp/odv-new && mkdir -p /tmp/odv-new && tar -xzf /tmp/omeka-dip-viewer-deploy.tar.gz -C /tmp/odv-new
test -f /tmp/odv-new/OmekaDipViewer/config/module.ini
# Pre-check on the target's own PHP BEFORE touching the live module: lint every PHP file, and load
# the bundled autoloader if one ships (catches Composer platform requirements). Abort on any error.
docker exec -u 0 "\$OID" rm -rf /tmp/odv-stage
docker cp /tmp/odv-new/OmekaDipViewer "\$OID:/tmp/odv-stage"
LINT="\$(docker exec "\$OID" sh -c 'find /tmp/odv-stage -name "*.php" -not -path "*/vendor/*" -exec php -l {} \; 2>&1 | grep -v "^No syntax errors"' || true)"
if [ -n "\$LINT" ]; then echo "pre-check failed (php -l):" >&2; echo "\$LINT" >&2; docker exec -u 0 "\$OID" rm -rf /tmp/odv-stage; exit 1; fi
if docker exec "\$OID" test -f /tmp/odv-stage/vendor/autoload.php; then
  docker exec "\$OID" php -r 'require "/tmp/odv-stage/vendor/autoload.php";' \
    || { echo "pre-check failed: bundled vendor/ does not load on this PHP" >&2; docker exec -u 0 "\$OID" rm -rf /tmp/odv-stage; exit 1; }
fi
docker exec -u 0 "\$OID" rm -rf /tmp/odv-stage
echo "pre-check: \$(docker exec "\$OID" php -r 'echo PHP_VERSION;') lint ok"
# Keep the server's own S3 config (not in git).
docker exec "\$OID" sh -c 'test -f $MODULE_DIR_IN_CONTAINER/config/dip-s3.config.php' \
  && docker cp "\$OID:$MODULE_DIR_IN_CONTAINER/config/dip-s3.config.php" /tmp/odv-new/OmekaDipViewer/config/dip-s3.config.php
OWNER="\$(docker exec "\$OID" stat -c %u:%g $MODULE_DIR_IN_CONTAINER)"
docker exec -u 0 "\$OID" sh -c 'rm -rf ${MODULE_DIR_IN_CONTAINER}.deploying && mv $MODULE_DIR_IN_CONTAINER ${MODULE_DIR_IN_CONTAINER}.deploying'
docker cp /tmp/odv-new/OmekaDipViewer "\$OID:$MODULE_DIR_IN_CONTAINER"
docker exec -u 0 "\$OID" chown -R "\$OWNER" $MODULE_DIR_IN_CONTAINER
cat > /tmp/odv-upgrade.php <<'PHP'
$UPGRADE_PHP
PHP
docker cp /tmp/odv-upgrade.php "\$OID:/tmp/odv-upgrade.php"
if ! docker exec "\$OID" php /tmp/odv-upgrade.php; then
  echo "upgrade failed; restoring previous module" >&2
  docker exec -u 0 "\$OID" sh -c 'rm -rf $MODULE_DIR_IN_CONTAINER && mv ${MODULE_DIR_IN_CONTAINER}.deploying $MODULE_DIR_IN_CONTAINER'
  exit 1
fi
docker exec -u 0 "\$OID" sh -c 'rm -rf ${MODULE_DIR_IN_CONTAINER}.deploying /tmp/odv-upgrade.php'
sleep 3   # OPcache revalidate_freq=2: new files are live after this
rm -rf /tmp/odv-new /tmp/odv-upgrade.php /tmp/omeka-dip-viewer-deploy.tar.gz
echo "$label: done"
REMOTE
}

verify() {
  sleep 2
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$VERIFY_URL")"
  echo "verify $VERIFY_URL -> HTTP $code"
  [[ "$code" == 200 ]] || die "verify page did not return 200"
  preflight
}

case "${1:-}" in
  --preflight) preflight ;;
  --rollback)
    [[ -f "${2:-}" ]] || die "usage: $0 --rollback LOCAL_COPY_OF_BACKUP.tar.gz (copy it from $STACK/backups first)"
    install_tarball "$(realpath "$2")" "rollback"; verify ;;
  ""|-h|--help) sed -n 2,16p "$0"; exit 0 ;;
  *)
    SRC="$(realpath "$1")"
    [[ -f "$SRC/config/module.ini" ]] || die "$SRC is not a module checkout (needs config/module.ini)"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    mkdir -p "$WORK/OmekaDipViewer"
    (cd "$SRC" && git archive HEAD) | tar -x -C "$WORK/OmekaDipViewer"
    # Production runs the module WITHOUT vendor/: the AWS SDK comes from the AnyCloud module, and a
    # locally built vendor/ may target a newer PHP (composer.lock pins symfony/filesystem 8.x, PHP 8.4)
    # than production's 8.3. Ship vendor/ only on request.
    if [[ "${DEPLOY_WITH_VENDOR:-0}" == 1 ]]; then
      [[ -d "$SRC/vendor" ]] || die "DEPLOY_WITH_VENDOR=1 but $SRC/vendor is missing"
      cp -a "$SRC/vendor" "$WORK/OmekaDipViewer/"
    fi
    echo "==> deploying $(grep -m1 '^version' "$SRC/config/module.ini") from $(git -C "$SRC" rev-parse --short HEAD)"
    tar -C "$WORK" -czf "$WORK/omeka-dip-viewer-deploy.tar.gz" OmekaDipViewer
    echo "==> preflight"; preflight
    install_tarball "$WORK/omeka-dip-viewer-deploy.tar.gz" "deploy"
    echo "==> verify"; verify ;;
esac
