FROM nginx:alpine

ARG HOST

COPY nginx.conf /tmp/tpl/nginx.conf

RUN sed 's/{{HOST}}/${HOST}/' /tmp/tpl/nginx.conf > /etc/nginx/nginx.conf
