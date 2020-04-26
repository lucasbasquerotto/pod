#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"

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

if [ -z "$command" ]; then
	error "No command entered (compose)."
fi

shift;

case "$command" in
	"up")
		sudo docker run -d "${@}"
		;;
	"exec-nontty")
		sudo docker exec -i "${@}"
		;;
	"run")
		sudo docker run --rm "${@}"
		;;
	"rm"|"build"|"stop"|"exec"|"restart"|"logs"|"ps")
		sudo docker "$command" "${@}"
		;;
	"sh"|"bash")
		sudo docker exec "${1}" /bin/"$command"
		;;
	*)
		error "$command: invalid command"
		;;
esac