#!/bin/bash
set -eou pipefail

command="${1:-}"
dir="$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)"
layer_dir="$(dirname "$dir")"
base_dir="$(dirname "$layer_dir")"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
    msg="This project must be in a directory structure of type [base_dir]/[layer_dir]/[this_repo]"
    msg="$msg with base_dir different than '' or '/'"
    echo -e "${RED}${msg}${NC}"
    exit 1
fi

pod_layer_dir="$dir"
app_layer_dir="$base_dir/app/{{ params.wordpress_dev_repo_dir }}"
local_seed_data="{{ params.local_seed_data }}"
remote_seed_data="{{ params.remote_seed_data }}"

if [ "$command" = "after-prepare" ]; then
    start="$(date '+%F %X')"
    echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"
    chmod +x $app_layer_dir/
    cp $pod_layer_dir/env/wordpress/.env $app_layer_dir/.env
    chmod +r $app_layer_dir/.env
    chmod 777 $app_layer_dir/web/app/uploads/
    echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
    end="$(date '+%F %X')"
    echo -e "${CYAN}env - $command - $start - $end${NC}"
elif [ "$command" = "deploy" ]; then
    start="$(date '+%F %X')"
    echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"
    cd "$dir"
    sudo docker-compose stop wordpress

    echo -e "${CYAN}$(date '+%F %X') - env - $command - composer install & update${NC}"
    sudo docker-compose up -d composer
    sudo docker-compose exec composer composer install
    sudo docker-compose exec composer composer update

    echo -e "${CYAN}$(date '+%F %X') - env - $command - setup${NC}"
    ./env/scripts/setup

    if [ ! -z "$local_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - env - $command - import local seed data${NC}"
        sudo docker-compose run --rm wordpress \
            wp --allow-root import ./"$local_seed_data" --authors=create
    fi

    if [ ! -z "$remote_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - env - $command - import local seed data${NC}"
        sudo docker-compose run --rm wordpress \
            curl -o ./tmp/tmp-seed-data.xml -k "$remote_seed_data"
        sudo docker-compose run --rm wordpress \
            wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create
        sudo docker-compose run --rm wordpress \
            rm -f ./tmp/tmp-seed-data.xml
    fi


    echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
    end="$(date '+%F %X')"
    echo -e "${CYAN}env - $command - $start - $end${NC}"
fi