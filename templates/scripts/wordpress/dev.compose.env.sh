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

if [ "$command" = "after-prepare" ]; then
    echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"
    chmod +x $app_layer_dir/
    cp $pod_layer_dir/env/wordpress/.env $app_layer_dir/.env
    chmod +r $app_layer_dir/.env
    echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
elif [ "$command" = "before-run" ]; then
    echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"
    cd "$dir"
    sudo docker-compose stop wordpress
    sudo docker-compose up -d mysql
    ./env/scripts/setup
    echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
fi