ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

ARG ENV_DIR

USER root

COPY $ENV_DIR/fluent.conf /fluentd/etc/

RUN chmod +rx /fluentd/etc/fluent.conf

USER fluent
