ARG MAIN_IMAGE
ARG MAIN_VERSION

FROM ${MAIN_IMAGE}:${MAIN_VERSION}

COPY env/wordpress/ /tmp/app/

RUN mv /tmp/app/wp-config.php /var/www/html/wp-config.php \
 && mv /tmp/app/apache2.conf /etc/apache2/apache2.conf \
 && mv /tmp/app/000-default.conf /etc/apache2/sites-enabled/000-default.config
