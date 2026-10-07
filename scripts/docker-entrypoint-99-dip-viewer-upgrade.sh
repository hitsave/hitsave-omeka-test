#!/bin/sh
# Apply OmekaDipViewer DB version when module.ini is ahead (bind-mounted dev module).
set -e
if [ -f /scripts/ensure-omeka-dip-viewer-upgrade.php ]; then
  php /scripts/ensure-omeka-dip-viewer-upgrade.php
fi
