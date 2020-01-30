ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

ARG ENV_DIR

COPY $ENV_DIR/test.yml /etc/test/conf.d/test.yml

RUN mkdir -p /var/log/test
