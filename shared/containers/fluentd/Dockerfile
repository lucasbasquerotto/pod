ARG IMAGE

FROM $IMAGE

USER root

COPY /env/fluentd/fluent.conf /fluentd/etc/fluent.conf

RUN mkdir -p /var/log/main \
 && chown fluent /var/log/main \
 && chmod +rx /fluentd/etc/fluent.conf

