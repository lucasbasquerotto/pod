#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

CYAN='\033[0;36m'
NC='\033[0m' # No Color

cd "$pod_full_dir"

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - remove old container${NC}"
sudo docker-compose rm -f --stop wordpress

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update database${NC}"
sudo docker-compose run --rm wordpress wp --allow-root \
    core update-db

echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - activate plugins${NC}"
sudo docker-compose run --rm wordpress wp --allow-root \
    plugin activate --all

if [ ! -z "$var_old_domain_host" ] && [ ! -z "$var_new_domain_host" ]; then
    echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update domain${NC}"
    sudo docker-compose run --rm wordpress wp --allow-root \
        search-replace "$var_old_domain_host" "$var_new_domain_host"
fi