ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY --chown=nginx:nginx /shared/containers/nginx/include/ /etc/nginx/include/
COPY --chown=nginx:nginx /env/nginx/conf/.htpasswd /etc/nginx/conf/
COPY --chown=nginx:nginx /env/nginx/nginx.conf /etc/nginx/
