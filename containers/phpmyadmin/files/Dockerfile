ARG PMA_IMAGE
ARG PMA_VERSION

FROM $PMA_IMAGE:$PMA_VERSION

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/phpmyadmin/config.user.inc.php /etc/phpmyadmin/config.user.inc.php
