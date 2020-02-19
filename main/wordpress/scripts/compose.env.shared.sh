#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

export "pod_shared_file_full=$pod_layer_dir/$scripts_dir/compose.shared.sh"

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

re_number='^[0-9]+$'

if [ -z "$command" ]; then
	echo -e "${RED}No command passed (env - shared).${NC}"
	exit 1
fi

shift;
	
start="$(date '+%F %X')"

case "$command" in
	"setup"|"backup")
		"$pod_shared_file_full" "$command"
		;;
	"setup:uploads")
    cd "$pod_full_dir"
		sudo docker-compose rm -f --stop wordpress
		"$pod_shared_file_full" "$command"
		;;
	"setup:db")
    cd "$pod_full_dir"
		sudo docker-compose rm -f --stop wordpress mysql
		"$pod_shared_file_full" "$command"
		;;
	"setup:db:new")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
    sudo docker-compose run --rm wordpress \
      wp --allow-root core install \
      --url="$setup_url" \
      --title="$setup_title" \
      --admin_user="$setup_admin_user" \
      --admin_password="$setup_admin_password" \
      --admin_email="$setup_admin_email"

    if [ ! -z "$setup_local_seed_data" ] || [ ! -z "$setup_remote_seed_data" ]; then
      echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
      "$pod_script_root_run_file_full" "$pod_vars_dir" deploy 

      if [ ! -z "$setup_local_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
        sudo docker-compose run --rm wordpress \
          wp --allow-root import ./"$setup_local_seed_data" --authors=create
      fi

      if [ ! -z "$setup_remote_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import remote seed data${NC}"
        sudo docker-compose run --rm wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$setup_remote_seed_data' \
          && wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
          && rm -f ./tmp/tmp-seed-data.xml"
      fi
    fi
    ;;
	*)
		echo -e "${RED}[env-shared] Invalid command: $command ${NC}"
		exit 1
    ;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"