#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

. "${DIR}/vars.sh"

layer_dir="$(dirname "$DIR")"
base_dir="$(dirname "$layer_dir")"

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
    msg="This project must be in a directory structure of type [base_dir]/[layer_dir]/[this_repo]"
    msg="$msg with base_dir different than '' or '/'"
    echo -e "${RED}${msg}${NC}"
    exit 1
fi

command="${1:-}"
shift

ctl_layer_dir="$base_dir/ctl"
pod_layer_dir="$DIR"
app_layer_dir="$base_dir/apps/$wordpress_dev_repo_dir"

start="$(date '+%F %X')"
echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"

case "$command" in
    "prepare")
        env_local_repo="$1"
        shift

        "$ctl_layer_dir/run" dev-cmd bash "/root/w/r/$env_local_repo/run" "${@}"

        sudo chmod +x "$app_layer_dir/"
        cp "$pod_layer_dir/$pod_dir/main/wordpress/.env" "$app_layer_dir/.env"
        chmod +r "$app_layer_dir/.env"
        chmod 777 "$app_layer_dir/web/app/uploads/"
        ;;
    "before-setup")
        cd "$DIR"
        sudo docker-compose rm --stop --force wordpress composer mysql
        sudo docker-compose up -d mysql composer
        sudo docker-compose exec composer composer install --verbose
        ;;
    "before-deploy")
        cd "$DIR"
        sudo docker-compose rm --stop --force wordpress composer mysql
        sudo docker-compose up -d mysql composer
        sudo docker-compose exec composer composer clear-cache
        sudo docker-compose exec composer composer update --verbose
        ;;
    "after-stop")
        "$ctl_layer_dir/run" stop
        ;;
    "after-rm")
        "$ctl_layer_dir/run" rm
        ;;
    *)
        echo -e "env - $command - nothing to run"
        ;;
esac

echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
end="$(date '+%F %X')"
echo -e "${CYAN}env - $command - $start - $end${NC}"