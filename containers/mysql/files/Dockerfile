ARG MYSQL_IMAGE
ARG MYSQL_VERSION

FROM $MYSQL_IMAGE:$MYSQL_VERSION

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/mysql/mysqld.cnf /etc/mysql/conf.d/mysqld.cnf

RUN mkdir -p /var/log/mysql \
 && chown -R mysql:mysql /var/log/mysql/ \
 && ls -la /var/log/mysql/
