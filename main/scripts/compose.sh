#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

main_file="${ORCHESTRATION_MAIN_FILE:-docker-compose.yml}"
run_file="${ORCHESTRATION_RUN_FILE:-docker-compose.run.yml}"
file=''

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

args=("$@")

while getopts ':u:-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		main ) file="$main_file";;
		run ) file="$run_file";;
		u|user )
			arg_user="${OPTARG:-}"

			if [ -z "$arg_user" ]; then
				arg_user="${2:-}"

				if [ -z "$arg_entrypoint" ]; then
					error "user not defined"
				fi

				shift;
			fi
			;;
		entrypoint )
			arg_entrypoint="${OPTARG:-}"

			if [ -z "$arg_entrypoint" ]; then
				arg_entrypoint="${2:-}"

				if [ -z "$arg_entrypoint" ]; then
					error "entrypoint not defined"
				fi

				shift;
			fi
			;;
		??* ) OPTIND=$((OPTIND-1)); break;;
		\? ) OPTIND=$((OPTIND-1));  break;;
	esac
done
shift $((OPTIND-1))

case "$command" in
	"up")
		cd "$pod_full_dir/"
		sudo docker-compose -f "$main_file" up -d --remove-orphans "${@}"
		;;
	"exec"|"exec-nontty")
		cd "$pod_full_dir/"

		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		container="$("$pod_script_env_file" ps -q "$service")"

		if [ -z "$container" ]; then
			error "[$command] container not found (or not running) for service $service"
		fi

		opts=()

		if [ "$command" = "exec-nontty" ]; then
			opts+=( "-i" )
		fi

		if [ -n "${arg_user:-}" ]; then
			opts+=( "--user" "${arg_user:-}" )
		fi

		if [ -n "${arg_entrypoint:-}" ]; then
			opts+=( "--entrypoint" "${arg_entrypoint:-}" )
		fi

		sudo docker exec ${opts[@]+"${opts[@]}"} "$container" "${@}"
		;;
	"run")
		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		opts=()

		if [ -n "${arg_user:-}" ]; then
			opts+=( "--user" "${arg_user:-}" )
		fi

		if [ -n "${arg_entrypoint:-}" ]; then
			opts+=( "--entrypoint" "${arg_entrypoint:-}" )
		fi

		cd "$pod_full_dir/"
		sudo docker-compose -f "${file:-$run_file}" run --rm --name="${service}_run" ${opts[@]+"${opts[@]}"} "$service" "${@}"
		;;
	"rm")
		cd "$pod_full_dir/"

		if [[ "${#args[@]}" -ne 0 ]]; then
			sudo docker-compose -f "${file:-$main_file}" rm --stop -v --force "${@}"
		else
			sudo docker-compose -f "${file:-$main_file}" rm --stop -v --force

			if [ -f "$run_file" ]; then
				sudo docker-compose -f "$run_file" rm --stop -v --force
			fi
		fi
		;;
	"build"|"stop")
		cd "$pod_full_dir/"

		if [[ "${#args[@]}" -ne 0 ]]; then
			sudo docker-compose -f "${file:-$main_file}" "$command" "${@}"
		else
			sudo docker-compose -f "${file:-$main_file}" "$command"

			if [ -f "$run_file" ]; then
				sudo docker-compose -f "$run_file" "$command"
			fi
		fi
		;;
	"restart"|"logs"|"ps")
		cd "$pod_full_dir/"
		sudo docker-compose -f "${file:-$main_file}" "$command" "${@}"
		;;
	"sh"|"ash"|"zsh"|"bash")
		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		cd "$pod_full_dir/"
		sudo docker-compose -f "${file:-$main_file}" exec "$service" /bin/"$command" "${@}"
		;;
	"system:df")
		sudo docker system df
		;;
	*)
		error "$command: invalid command"
		;;
esac