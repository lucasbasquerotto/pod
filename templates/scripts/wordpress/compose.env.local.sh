#!/bin/bash
set -eou pipefail

wordpress_dev_repo_dir="{{ params.wordpress_dev_repo_dir }}"

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
app_layer_dir="$base_dir/app/$wordpress_dev_repo_dir"

start="$(date '+%F %X')"
echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"

case "$command" in
    "after-prepare")
        chmod +x $app_layer_dir/
        cp $pod_layer_dir/env/wordpress/.env $app_layer_dir/.env
        chmod +r $app_layer_dir/.env
        chmod 777 $app_layer_dir/web/app/uploads/
        ;;
    "before-setup")
        cd "$dir"
        sudo docker-compose rm --stop --force wordpress composer mysql
        sudo docker-compose up -d mysql composer
        sudo docker-compose exec composer composer install
        ;;
    "before-deploy")
        cd "$dir"
        sudo docker-compose rm --stop --force wordpress composer mysql
        sudo docker-compose up -d composer
        sudo docker-compose exec composer composer update
        ;;
    *)
        echo -e "env - $command - nothing to run"
        ;;
esac

echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
end="$(date '+%F %X')"
echo -e "${CYAN}env - $command - $start - $end${NC}"