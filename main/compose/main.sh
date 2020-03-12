#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

RED='\033[0;31m'
NC='\033[0m' # No Color

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	error "This project must not be in the '/' directory"
fi

command="${1:-}"
run_file="docker-compose.run.yml"

if [ -z "$command" ]; then
	error "No command entered (compose)."
fi

shift;

case "$command" in
	"up")
		cd "$pod_full_dir/"
		sudo docker-compose up -d --remove-orphans "${@}"
		;;
	"exec-nontty")
		cd "$pod_full_dir/"

		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		sudo docker exec -i "$("$pod_script_env_file" ps -q "$service")" "${@}"
		;;
	"run")
		cd "$pod_full_dir/"
		sudo docker-compose -f "$run_file" run --rm "${@}"
		;;
	"rm")
		cd "$pod_full_dir/"
		sudo docker-compose rm --stop -v --force "${@}"

		if [ -f "$run_file" ] && [[ "$#" -eq 0 ]]; then
			sudo docker-compose -f "$run_file" rm --stop -v --force "${@}"
		fi
		;;
	"build"|"stop")
		cd "$pod_full_dir/"
		sudo docker-compose "$command" "${@}"

		if [ -f "$run_file" ] && [[ "$#" -eq 0 ]]; then
			sudo docker-compose -f "$run_file" "$command" "${@}"
		fi
		;;
	"exec"|"restart"|"logs"|"ps")
		cd "$pod_full_dir/"
		sudo docker-compose "$command" "${@}"
		;;
	"ps-run")
		cd "$pod_full_dir/"
		
		if [ -f "$run_file" ]; then
			sudo docker-compose -f "$run_file" ps "${@}"
		fi
		;;
	"sh"|"bash")
		cd "$pod_full_dir/"
		sudo docker-compose exec "${1}" /bin/"$command"
		;;
	*)
		error "$command: invalid command"
		;;
esac