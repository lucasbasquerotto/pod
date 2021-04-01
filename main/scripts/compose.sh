#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

main_file="${ORCHESTRATION_MAIN_FILE:-docker-compose.yml}"
run_file="${ORCHESTRATION_RUN_FILE:-docker-compose.run.yml}"
file=''

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

# shellcheck disable=SC2214
while getopts ':s:u:-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		main ) file="$main_file";;
		run ) file="$run_file";;
		s )
			arg_signal="${2:-}"

			if [ -z "$arg_signal" ]; then
				error "signal not defined"
			fi

			shift;
			;;
		u|user )
			arg_user="${OPTARG:-}"

			if [ -z "$arg_user" ]; then
				arg_user="${2:-}"

				if [ -z "$arg_user" ]; then
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
		cd "$pod_layer_dir/"
		sudo docker-compose -f "$main_file" up -d --remove-orphans "${@}"
		;;
	"down")
		cd "$pod_layer_dir/"
		sudo docker-compose -f "$main_file" down "${@}"
		;;
	"exec"|"exec-nontty")
		cd "$pod_layer_dir/"

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

		cd "$pod_layer_dir/"
		sudo docker-compose -f "${file:-$run_file}" run --rm --name="${service}_run" ${opts[@]+"${opts[@]}"} "$service" "${@}"
		;;
	"rm")
		cd "$pod_layer_dir/"

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
		cd "$pod_layer_dir/"

		if [[ "${#args[@]}" -ne 0 ]]; then
			sudo docker-compose -f "${file:-$main_file}" "$command" "${@}"
		else
			sudo docker-compose -f "${file:-$main_file}" "$command"

			if [ -f "$run_file" ]; then
				sudo docker-compose -f "$run_file" "$command"
			fi
		fi
		;;
	"kill")
		cd "$pod_layer_dir/"

		sudo docker-compose -f "${file:-$main_file}" kill "${args[@]}"
		;;
	"restart"|"logs"|"ps")
		cd "$pod_layer_dir/"
		sudo docker-compose -f "${file:-$main_file}" "$command" "${@}"
		;;
	"sh"|"ash"|"zsh"|"bash")
		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		cd "$pod_layer_dir/"
		sudo docker-compose -f "${file:-$main_file}" exec "$service" /bin/"$command" "${@}"
		;;
	"system:df")
		sudo docker system df
		;;
	*)
		error "$command: invalid command"
		;;
esac