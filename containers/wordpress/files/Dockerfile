ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

ARG ENV_DIR
ARG WORDPRESS_INI_FILE_TYPE

COPY --chown=www-data:www-data $ENV_DIR/.env /var/www/html/

RUN mv "$PHP_INI_DIR/php.ini-$WORDPRESS_INI_FILE_TYPE" "$PHP_INI_DIR/php.ini" 

ENV PORT 80
ENTRYPOINT []
CMD sed -i "s/80/$PORT/g" \
    /etc/apache2/sites-available/000-default.conf \
    /etc/apache2/ports.conf \
 && docker-php-entrypoint apache2-foreground
