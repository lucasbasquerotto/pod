#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

# shellcheck disable=SC2154
ctx_full_name="${var_run__general__ctx_full_name}"

main_project="${ctx_full_name}-main"
main_file="${var_orchestration__main_file:-docker-compose.yml}"

run_project="${ctx_full_name}-run"
run_file="${var_orchestration__run_file:-docker-compose.run.yml}"

project=''
file=''

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

# shellcheck disable=SC2214
while getopts ':its:u:-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		main ) project="$main_project"; file="$main_file";;
		run ) project="$run_project"; file="$run_file";;
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
		i|interactive ) arg_interactive='true';;
		t|tty ) arg_tty='true';;
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
		sudo docker-compose --project-name "$main_project" -f "$main_file" \
			up -d --remove-orphans "${@}" \
			1>&2 2> >(grep -v up-to-date)
		;;
	"down")
		cd "$pod_layer_dir/"
		sudo docker-compose --project-name "$main_project" -f "$main_file" down "${@}"
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

		if [ "$command" = "exec-nontty" ] || [ "${arg_interactive:-}" = 'true' ]; then
			opts+=( "-i" )
		fi

		if [ "${arg_tty:-}" = 'true' ]; then
			opts+=( "-t" )
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
		sudo docker-compose --project-name "${project:-$run_project}" -f "${file:-$run_file}" run --rm --name="${service}_run" ${opts[@]+"${opts[@]}"} "$service" "${@}"
		;;
	"rm")
		cd "$pod_layer_dir/"

		if [[ "${#args[@]}" -ne 0 ]]; then
			sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" rm --stop -v --force "${@}"
		else
			sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" rm --stop -v --force

			if [ -f "$run_file" ]; then
				sudo docker-compose --project-name "${project:-$run_project}" -f "$run_file" rm --stop -v --force
			fi
		fi
		;;
	"build"|"stop")
		cd "$pod_layer_dir/"

		if [[ "${#args[@]}" -ne 0 ]]; then
			sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" "$command" "${@}"
		else
			sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" "$command"

			if [ -f "$run_file" ]; then
				sudo docker-compose --project-name "${project:-$run_project}" -f "$run_file" "$command"
			fi
		fi
		;;
	"kill")
		cd "$pod_layer_dir/"

		sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" kill "${args[@]}"
		;;
	"restart"|"logs"|"ps")
		cd "$pod_layer_dir/"
		sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" "$command" "${@}"
		;;
	"sh"|"ash"|"zsh"|"bash")
		service="${1:-}"

		if [ -z "$service" ]; then
			error "[$command] service not specified"
		fi

		shift;

		cd "$pod_layer_dir/"
		sudo docker-compose --project-name "${project:-$main_project}" -f "${file:-$main_file}" exec "$service" "$command" "${@}"
		;;
	"system:df")
		sudo docker system df
		;;
	*)
		error "$command: invalid command"
		;;
esac