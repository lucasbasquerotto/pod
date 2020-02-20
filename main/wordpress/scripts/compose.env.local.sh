#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_env_shared_file_full="$pod_layer_dir/$scripts_dir/compose.env.shared.sh"

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

ctl_layer_dir="$base_dir/ctl"
app_layer_dir="$base_dir/apps/$wordpress_dev_repo_dir"

command="${1:-}"
shift

start="$(date '+%F %X')"
echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"

case "$command" in
  "prepare")
    "$ctl_layer_dir/run" dev-cmd bash "/root/w/r/$env_local_repo/run" "${@}"

    sudo chmod +x "$app_layer_dir/"
    cp "$pod_full_dir/main/wordpress/.env" "$app_layer_dir/.env"
    chmod +r "$app_layer_dir/.env"
    chmod 777 "$app_layer_dir/web/app/uploads/"
    ;;
	"setup")
    cd "$pod_full_dir"
    sudo docker-compose rm --stop --force wordpress composer mysql
    sudo docker-compose up -d mysql composer
    sudo docker-compose exec composer composer install --verbose
		"$pod_env_shared_file_full" "$command"
		;;
  "deploy")
    cd "$pod_full_dir"
    sudo docker-compose rm --stop --force wordpress composer mysql
    sudo docker-compose up -d mysql composer
    sudo docker-compose exec composer composer clear-cache
    sudo docker-compose exec composer composer update --verbose
		"$pod_env_shared_file_full" "$command" "$@"
    ;;
  "stop"|"rm")
		"$pod_env_shared_file_full" "$command" "$@"
    "$ctl_layer_dir/run" "$command"
    ;;
	*)
		"$pod_env_shared_file_full" "$command" "$@"
    ;;
esac

echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
end="$(date '+%F %X')"
echo -e "${CYAN}env - $command - $start - $end${NC}"