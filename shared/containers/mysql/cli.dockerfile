ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

RUN mkdir -p /var/log/mysql \
 && chown -R mysql:mysql /var/log/mysql/ \
 && ls -la /var/log/mysql/
