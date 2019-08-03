#!/bin/bash
set -eou pipefail

sudo docker-compose run --rm wordpress \
    wp --allow-root core install \
    --url='{{ params.url }}' \
    --title='{{ params.title }}' \
    --admin_user='{{ params.admin_user }}' \
    --admin_password='{{ params.admin_password }}' \
    --admin_email='{{ params.admin_email }}'
sudo docker-compose run --rm wordpress wp --allow-root plugin activate --all
sudo docker-compose run --rm wordpress wp --allow-root core update-db