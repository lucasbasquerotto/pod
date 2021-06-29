#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
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
	"network")
		sudo docker network "${@}"
		;;
	*)
		error "$command: invalid command"
		;;
esac