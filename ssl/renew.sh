#!/bin/sh
set -e
parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)
docker run -it -v /docker/vol/ssl:/etc/ssl -v "$parent_path":/etc/input httpd:2.4.35 openssl x509 -in /etc/ssl/server.csr -out /etc/ssl/server.crt -req -signkey /etc/ssl/server.key -days 36500 -sha256 -extfile /etc/input/v3.ext