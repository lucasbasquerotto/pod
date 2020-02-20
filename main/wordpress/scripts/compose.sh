#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_shared_file_full="$pod_layer_dir/$var_scripts_dir/compose.shared.sh"

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
	echo -e "${RED}No command entered (compose).${NC}"
	exit 1
fi

shift;
	
start="$(date '+%F %X')"

case "$command" in
	"up")
		cd "$pod_full_dir/"
		sudo docker-compose up -d --remove-orphans $@
		;;
	"rm")
		cd "$pod_full_dir/"
		sudo docker-compose rm --stop -v --force $@
		;;
	"build"|"run"|"stop"|"exec"|"restart"|"logs"|"ps")
		cd "$pod_full_dir/"
		sudo docker-compose "$command" ${@}
		;;
	"sh"|"bash")
		cd "$pod_full_dir/"
		sudo docker-compose exec "${1}" /bin/"$command"
		;;
	*)
		"$pod_shared_file_full" "$command" "$@"
		;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"