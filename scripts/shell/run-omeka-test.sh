#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/ensure-local-config.sh"
python3 "$ROOT/scripts/shell/sync-docker-config.py"

docker compose build omeka
docker compose up -d mariadb omeka

PUBLIC_URL="$(python3 -c "import yaml; print(yaml.safe_load(open('$ROOT/config/omeka-test/settings.yaml'))['omeka'].get('public_url','http://127.0.0.1:8088').rstrip('/'))")"
echo "Waiting for Omeka at ${PUBLIC_URL} ..."
for i in $(seq 1 60); do
  if curl -fsS "${PUBLIC_URL}/login" >/dev/null 2>&1; then
    echo "Omeka is up."
    break
  fi
  sleep 5
done

docker compose exec -T -u root omeka sh -c 'rm -rf /var/www/html/volume/modules/HitSaveDipViewer /var/www/html/volume/modules/ArchivematicaConnector /var/www/html/volume/modules/Exports /var/www/html/modules/HitSaveDipViewer /var/www/html/modules/ArchivematicaConnector /var/www/html/modules/Exports' || true
docker compose exec -T omeka omeka-s-cli module:install OmekaDipViewer || true
docker compose exec -T omeka omeka-s-cli module:enable OmekaDipViewer || true
docker compose exec -T omeka php /scripts/ensure-omeka-dip-viewer-upgrade.php || true
docker compose exec -T omeka omeka-s-cli module:install Common || true
docker compose exec -T omeka omeka-s-cli module:enable Common || true
docker compose exec -T omeka omeka-s-cli module:install Ark || true
docker compose exec -T omeka omeka-s-cli module:enable Ark || true
docker compose exec -T omeka php /scripts/ensure-omeka-ark-module.php || true
docker compose exec -T -u root omeka php /scripts/ensure-omeka-test-site.php || true
docker compose exec -T -u root omeka php /scripts/ensure-press-item-set.php || true
docker compose exec -T -u root omeka php /scripts/ensure-press-material-site-page.php || true
docker compose exec -T -u root omeka php /scripts/ensure-batch-listing-site-page.php || true

echo "Admin: ${PUBLIC_URL}/admin (see config/omeka-test/settings.yaml for credentials)"
echo "Ingest + upload: docs/build-real-dip.md (docker compose in hitsave-archiver; source host.env from archiver-config)"
