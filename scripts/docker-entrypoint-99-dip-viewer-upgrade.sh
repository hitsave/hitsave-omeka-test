#!/bin/sh
# Apply OmekaDipViewer DB version when module.ini is ahead (bind-mounted dev module).
set -e
if [ -f /scripts/ensure-omeka-dip-viewer-upgrade.php ]; then
  php /scripts/ensure-omeka-dip-viewer-upgrade.php
fi
# Bind-mounted module updates do not recycle dip-pool workers; reload PHP-FPM.
if [ -n "${PHP_FPM_PID:-}" ] && kill -0 "$PHP_FPM_PID" 2>/dev/null; then
  kill -USR2 "$PHP_FPM_PID" 2>/dev/null || true
elif pidof php-fpm84 >/dev/null 2>&1; then
  kill -USR2 "$(pidof php-fpm84)" 2>/dev/null || true
fi
