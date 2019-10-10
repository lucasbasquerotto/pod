FROM {{ params.nginx_image }}:{{ params.nginx_version }}

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/nginx/ /etc/nginx/
