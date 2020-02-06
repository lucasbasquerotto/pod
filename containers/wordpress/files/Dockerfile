ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

ARG ENV_DIR
ARG WORDPRESS_INI_FILE_TYPE

COPY $ENV_DIR/* /tmp/dockerfile/

RUN set -eou; \
  mv "$PHP_INI_DIR/php.ini-$WORDPRESS_INI_FILE_TYPE" "$PHP_INI_DIR/php.ini"; \
  mv /tmp/dockerfile/.env /var/www/html/; \
  chown www-data:www-data /var/www/html/.env; \
  if [ -f /tmp/dockerfile/apache.conf ]; then \
    mv /tmp/dockerfile/apache.conf /etc/apache2/sites-available/000-default.conf; \
    chown www-data:www-data /etc/apache2/sites-available/000-default.conf; \
    echo "" > /etc/apache2/ports.conf; \
  fi
