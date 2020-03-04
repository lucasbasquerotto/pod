ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY . /tmp/dockerfile/

RUN set -eux; \
	if [ -f /tmp/dockerfile/.s3cfg ]; then \
    mv /tmp/dockerfile/.s3cfg /root/.s3cfg; \
  fi; \
	if [ -d /tmp/dockerfile/aws ]; then \
    mv /tmp/dockerfile/aws/ /root/.aws/; \
  fi