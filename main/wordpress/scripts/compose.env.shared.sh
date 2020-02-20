#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_file_full="$pod_layer_dir/$var_scripts_dir/$var_script_run_file"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	msg="This project must not be in the '/' directory"
	echo -e "${RED}${msg}${NC}"
	exit 1
fi

command="${1:-}"

if [ -z "$command" ]; then
	echo -e "${RED}No command entered (env - shared).${NC}"
	exit 1
fi

shift;
	
start="$(date '+%F %X')"

case "$command" in
	"setup:uploads")
    cd "$pod_full_dir"
		sudo docker-compose rm -f --stop wordpress
		"$pod_script_run_file_full" "$command"
		;;
	"setup:db")
    cd "$pod_full_dir"
		sudo docker-compose rm -f --stop wordpress mysql
		"$pod_script_run_file_full" "$command"
		;;
	"setup:db:new")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
    sudo docker-compose run --rm wordpress \
      wp --allow-root core install \
      --url="$var_setup_url" \
      --title="$var_setup_title" \
      --admin_user="$var_setup_admin_user" \
      --admin_password="$var_setup_admin_password" \
      --admin_email="$var_setup_admin_email"

    if [ ! -z "$var_setup_local_seed_data" ] || [ ! -z "$var_setup_remote_seed_data" ]; then
      echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
      "$pod_script_env_file" deploy 

      if [ ! -z "$var_setup_local_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
        sudo docker-compose run --rm wordpress \
          wp --allow-root import ./"$var_setup_local_seed_data" --authors=create
      fi

      if [ ! -z "$var_setup_remote_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import remote seed data${NC}"
        sudo docker-compose run --rm wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$var_setup_remote_seed_data' \
          && wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
          && rm -f ./tmp/tmp-seed-data.xml"
      fi
    fi
		;;
	"deploy")
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
		;;
	*)
    "$pod_script_run_file_full" "$command" "$@"
    ;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"