ARG IMAGE
ARG VERSION

FROM $IMAGE:$VERSION

COPY --chown=nginx:nginx /shared/containers/nginx/include/ /etc/nginx/include/
COPY --chown=nginx:nginx /env/nginx/auth/ /etc/nginx/auth/
COPY --chown=nginx:nginx /env/nginx/nginx.conf /etc/nginx/
