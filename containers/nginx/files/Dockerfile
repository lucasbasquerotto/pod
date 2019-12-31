ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

ARG ENV_DIR

COPY $ENV_DIR/nginx.conf /etc/nginx/nginx.conf
COPY $ENV_DIR/includes/ /etc/nginx/includes/
