ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY --chown=postgres:postgres /env/mysql/init.sql /docker-entrypoint-initdb.d/