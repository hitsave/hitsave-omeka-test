#!/usr/bin/env bash
# Pull resource templates (and mirror bundle) from production, apply templates on test only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 "$ROOT/scripts/shell/pull-omeka-prod-mirror.py"
docker compose exec -T -u root omeka php /scripts/apply-omeka-resource-templates.php
