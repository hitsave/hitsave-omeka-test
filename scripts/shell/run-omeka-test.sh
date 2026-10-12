#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/ensure-local-config.sh"
python3 "$ROOT/scripts/shell/sync-docker-config.py"

COMPOSE_FILES=(-f docker-compose.yml)
DIP_S3="${OMEKA_DIP_VIEWER_MODULE:-$ROOT/../omeka-dip-viewer}/config/dip-s3.config.php"
if [[ -f "$DIP_S3" ]]; then
  COMPOSE_FILES+=(-f docker-compose.s3-direct.yml)
  echo "Using Wasabi S3 overlay (dip-s3.config.php found)."
fi

docker compose "${COMPOSE_FILES[@]}" build omeka
docker compose "${COMPOSE_FILES[@]}" up -d mariadb omeka

PUBLIC_URL="$(python3 -c "import yaml; print(yaml.safe_load(open('$ROOT/config/omeka-test/settings.yaml'))['omeka'].get('public_url','http://127.0.0.1:8088').rstrip('/'))")"
echo "Waiting for Omeka at ${PUBLIC_URL} ..."
for i in $(seq 1 60); do
  if curl -fsS "${PUBLIC_URL}/login" >/dev/null 2>&1; then
    echo "Omeka is up."
    break
  fi
  sleep 5
done

dc() { docker compose "${COMPOSE_FILES[@]}" "$@"; }

dc exec -T -u root omeka sh -c 'rm -rf /var/www/html/volume/modules/HitSaveDipViewer /var/www/html/volume/modules/ArchivematicaConnector /var/www/html/volume/modules/Exports /var/www/html/modules/HitSaveDipViewer /var/www/html/modules/ArchivematicaConnector /var/www/html/modules/Exports' || true
dc exec -T omeka omeka-s-cli module:install OmekaDipViewer || true
dc exec -T omeka omeka-s-cli module:enable OmekaDipViewer || true
dc exec -T omeka php /scripts/ensure-omeka-dip-viewer-upgrade.php || true
dc exec -T omeka omeka-s-cli module:install Common || true
dc exec -T omeka omeka-s-cli module:enable Common || true
dc exec -T omeka omeka-s-cli module:install Ark || true
dc exec -T omeka omeka-s-cli module:enable Ark || true
dc exec -T omeka php /scripts/ensure-omeka-ark-module.php || true
dc exec -T -u root omeka php /scripts/ensure-omeka-test-site.php || true
dc exec -T -u root omeka php /scripts/ensure-press-item-set.php || true
dc exec -T -u root omeka php /scripts/ensure-press-material-site-page.php || true
dc exec -T -u root omeka php /scripts/ensure-batch-listing-site-page.php || true
dc exec -T -u root omeka php /scripts/ensure-test-items-public.php || true

echo "Admin: ${PUBLIC_URL}/admin (see config/omeka-test/settings.yaml for credentials)"
echo "Ingest + upload: docs/build-real-dip.md (docker compose in hitsave-archiver; source host.env from archiver-config)"
