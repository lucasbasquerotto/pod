#!/bin/bash
set -eou pipefail

. "${DIR}/vars.sh"

CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - remove old container${NC}"
sudo docker-compose rm -f --stop wordpress

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update database${NC}"
sudo docker-compose run --rm wordpress wp --allow-root \
    core update-db

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - activate plugins${NC}"
sudo docker-compose run --rm wordpress wp --allow-root \
    plugin activate --all

if [ ! -z "$old_domain_host" ] && [ ! -z "$new_domain_host" ]; then
    echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update domain${NC}"
    sudo docker-compose run --rm wordpress wp --allow-root \
        search-replace "$old_domain_host" "$new_domain_host"
fi