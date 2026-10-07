FROM erseco/alpine-omeka-s:latest

USER root

ARG COMMON_MODULE_VERSION=3.4.93
ARG ARK_MODULE_VERSION=3.5.17
ARG OMEKA_DIP_VIEWER_REF=v0.3.30
ARG FOUNDATION_REF=v1.5.3
ARG HITSAVE_THEME_REPO=https://github.com/hitsave/hitsave-archive-theme.git

RUN apk add --no-cache git \
    && git clone --depth 1 --branch "${COMMON_MODULE_VERSION}" \
      https://gitlab.com/Daniel-KM/Omeka-S-module-Common.git /var/www/html/volume/modules/Common \
    && git clone --depth 1 --branch "${ARK_MODULE_VERSION}" \
      https://gitlab.com/Daniel-KM/Omeka-S-module-Ark.git /var/www/html/volume/modules/Ark \
    && cd /var/www/html/volume/modules/Ark && composer install --no-dev --no-interaction --prefer-dist

RUN git clone --depth 1 --branch "${OMEKA_DIP_VIEWER_REF}" \
      https://github.com/hitsave/omeka-dip-viewer.git /var/www/html/volume/modules/OmekaDipViewer

RUN git clone --depth 1 --branch "${FOUNDATION_REF}" \
      https://github.com/omeka-s-themes/foundation.git /tmp/foundation \
    && git clone --depth 1 "${HITSAVE_THEME_REPO}" /tmp/hitsave-archive-theme \
    && chmod +x /tmp/hitsave-archive-theme/scripts/build-hitsave-archive-theme.sh \
    && /tmp/hitsave-archive-theme/scripts/build-hitsave-archive-theme.sh \
      /tmp/foundation /var/www/html/volume/themes/HitSaveArchive /tmp/hitsave-archive-theme \
    && rm -rf /tmp/foundation /tmp/hitsave-archive-theme

COPY scripts/docker-entrypoint-99-dip-viewer-upgrade.sh /docker-entrypoint-init.d/99-dip-viewer-upgrade.sh
COPY scripts/php/ensure-omeka-dip-viewer-upgrade.php /scripts/ensure-omeka-dip-viewer-upgrade.php

RUN sed -i -E 's/client_max_body_size[[:space:]]+[0-9]+[mM]/client_max_body_size 1024M/' /etc/nginx/nginx.conf \
    && chmod +x /docker-entrypoint-init.d/99-dip-viewer-upgrade.sh \
    && chown -R nobody:nobody /var/www/html/volume/modules \
      /var/www/html/volume/themes/HitSaveArchive /var/www/html/volume/modules/Ark/vendor

USER nobody
