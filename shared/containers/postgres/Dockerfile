ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY --chown=postgres:postgres /env/postgres/init.sql /docker-entrypoint-initdb.d/