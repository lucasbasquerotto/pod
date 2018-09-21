ARG WILDFLY_VERSION

FROM jboss/wildfly:${WILDFLY_VERSION}

COPY ./config/ /opt/jboss/wildfly/standalone/configuration/

USER root

RUN chown -R jboss:jboss /opt/jboss/wildfly/standalone/configuration

USER jboss

RUN /opt/jboss/wildfly/bin/add-user.sh monitor Monitor#70365 --silent

CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0", "-bmanagement", "0.0.0.0"]
