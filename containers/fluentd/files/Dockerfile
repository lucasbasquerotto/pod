ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

USER root

COPY fluent.conf /fluentd/etc/

RUN chmod +rx /fluentd/etc/fluent.conf

USER fluent
