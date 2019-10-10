FROM {{ params.pma_image }}:{{ params.pma_version }}

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/phpmyadmin/config.user.inc.php /etc/phpmyadmin/config.user.inc.php
