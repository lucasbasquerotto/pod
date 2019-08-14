#!/bin/bash
set -eou pipefail

CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}$(date '+%F %X') - setup (app) - remove old container${NC}"
sudo docker-compose rm -f --stop wordpress

echo -e "${CYAN}$(date '+%F %X') - setup (app) - installation${NC}"
sudo docker-compose run --rm wordpress \
    wp --allow-root core install \
    --url='{{ params.url }}' \
    --title='{{ params.title }}' \
    --admin_user='{{ params.admin_user }}' \
    --admin_password='{{ params.admin_password }}' \
    --admin_email='{{ params.admin_email }}'

echo -e "${CYAN}$(date '+%F %X') - setup (app) - update database${NC}"
sudo docker-compose run --rm wordpress wp --allow-root core update-db

echo -e "${CYAN}$(date '+%F %X') - setup (app) - activate plugins${NC}"
sudo docker-compose run --rm wordpress wp --allow-root plugin activate --all