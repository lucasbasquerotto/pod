ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY --chown=mysql:mysql /shared/containers/mysql/mysqld.cnf /etc/mysql/conf.d/mysqld.cnf
COPY --chown=mysql:mysql /env/mysql/init.sql /docker-entrypoint-initdb.d/

RUN mkdir -p /var/log/mysql \
 && chown -R mysql:mysql /var/log/mysql/ \
 && ls -la /var/log/mysql/
