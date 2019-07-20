FROM {{ params.wordpress_image }}:{{ params.wordpress_version }}

ENV APACHE_DOCUMENT_ROOT /main

COPY env/wordpress/ /tmp/app/

RUN mkdir -p $APACHE_DOCUMENT_ROOT \
 && mkdir -p $APACHE_DOCUMENT_ROOT/wp-content \
 && mv /tmp/app/wp-config.php $APACHE_DOCUMENT_ROOT/wp-config.php \
#  && mv /tmp/app/apache2.conf /etc/apache2/apache2.conf \
#  && mv /tmp/app/000-default.conf /etc/apache2/sites-enabled/000-default.config \
 && sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
 && chown -R www-data:www-data $APACHE_DOCUMENT_ROOT

WORKDIR $APACHE_DOCUMENT_ROOT