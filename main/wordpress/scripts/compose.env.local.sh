#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

export "pod_env_shared_file_full=$pod_layer_dir/$scripts_dir/compose.env.shared.sh"

pod_layer_base_dir="$(dirname "$pod_layer_dir")"
base_dir="$(dirname "$pod_layer_base_dir")"

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
  msg="This project must be in a directory structure of type"
  msg="$msg [base_dir]/[pod_layer_base_dir]/[this_repo] with"
  msg="$msg base_dir different than '' or '/' instead of $pod_layer_dir"
  echo -e "${RED}${msg}${NC}"
  exit 1
fi

command="${1:-}"
shift

strict=true

if [ "$command" = "hook" ]; then
  command="${1:-}"
  shift
  strict=false
fi

ctl_layer_dir="$base_dir/ctl"
app_layer_dir="$base_dir/apps/$wordpress_dev_repo_dir"

start="$(date '+%F %X')"
echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"

case "$command" in
  "prepare")
    env_local_repo="$1"
    shift

    "$ctl_layer_dir/run" dev-cmd bash "/root/w/r/$env_local_repo/run" "${@}"

    sudo chmod +x "$app_layer_dir/"
    cp "$pod_full_dir/main/wordpress/.env" "$app_layer_dir/.env"
    chmod +r "$app_layer_dir/.env"
    chmod 777 "$app_layer_dir/web/app/uploads/"
    ;;
  "deploy:before")
    cd "$pod_full_dir"
    sudo docker-compose rm --stop --force wordpress composer mysql
    sudo docker-compose up -d mysql composer
    sudo docker-compose exec composer composer clear-cache
    sudo docker-compose exec composer composer update --verbose
    ;;
  "stop:after")
    "$ctl_layer_dir/run" stop
    ;;
  "rm:after")
    "$ctl_layer_dir/run" rm
    ;;
	"setup")
    cd "$pod_full_dir"
    sudo docker-compose rm --stop --force wordpress composer mysql
    sudo docker-compose up -d mysql composer
    sudo docker-compose exec composer composer install --verbose

		"$pod_env_shared_file_full" "$command"
		;;
	"setup:uploads"|"setup:db"|"setup:db:new"|"backup")
		"$pod_env_shared_file_full" "$command"
		;;
	*)
    if [ "$strict" = "true" ]; then
      echo -e "${RED}[env] Invalid command: $command ${NC}"
    else
      echo -e "env - $command - nothing to run"
    fi
    ;;
esac

echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
end="$(date '+%F %X')"
echo -e "${CYAN}env - $command - $start - $end${NC}"