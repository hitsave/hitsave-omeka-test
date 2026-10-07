#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 "$ROOT/scripts/shell/pull-omeka-prod-mirror.py"

docker compose build omeka
docker compose up -d omeka
sleep 6
docker compose exec -T -u root omeka php /scripts/apply-omeka-prod-mirror.php
docker compose restart omeka

PUBLIC="$(python3 -c "import yaml; d=yaml.safe_load(open('$ROOT/config/omeka-test/settings.yaml')); print(d['omeka'].get('public_url','http://127.0.0.1:8088').rstrip('/'))")"
SLUG="$(python3 -c "import yaml; d=yaml.safe_load(open('$ROOT/config/omeka-test/settings.yaml')); print(d['omeka'].get('site_slug','hitsave-test'))")"
echo "Test site: ${PUBLIC}/s/${SLUG}"
