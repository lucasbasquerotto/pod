FROM {{ params.wordpress_image }}:{{ params.wordpress_version }}

ARG POD_ENV_DIR

COPY --chown=www-data:www-data $POD_ENV_DIR/wordpress/.env /var/www/html/

RUN mv "$PHP_INI_DIR/php.ini-{{ params.ini_file_type }}" "$PHP_INI_DIR/php.ini" 
