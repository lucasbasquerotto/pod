FROM {{ params.wordpress_image }}:{{ params.wordpress_version }}

COPY --chown=www-data:www-data env/wordpress/.env /var/www/html/

{% set ini_file_type = ((params.env == 'development') | ternary('development', 'production')) -%}

RUN mv "$PHP_INI_DIR/php.ini-{{ ini_file_type }}" "$PHP_INI_DIR/php.ini" 
