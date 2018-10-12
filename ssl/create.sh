#!/bin/sh
set -e
parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)
docker run -it -v /docker/vol/ssl:/etc/ssl -v "$parent_path":/etc/input httpd:2.4.35 /usr/bin/openssl req -new -newkey sha:256 -nodes -keyout server.key -out server.csr -extfile /etc/input/v3.ext