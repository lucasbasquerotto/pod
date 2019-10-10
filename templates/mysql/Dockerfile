FROM {{ params.mysql_image }}:{{ params.mysql_version }}

ARG POD_ENV_DIR

COPY $POD_ENV_DIR/mysql/mysqld.cnf /etc/mysql/conf.d/mysqld.cnf
