#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

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

args=("$@")

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}" ;;
		container_type ) arg_container_type="${OPTARG:-}" ;;
		registry_api_base_url ) arg_registry_api_base_url="${OPTARG:-}" ;;
		registry_host ) arg_registry_host="${OPTARG:-}" ;;
		registry_port ) arg_registry_port="${OPTARG:-}" ;;
		repository ) arg_repository="${OPTARG:-}" ;;
		version ) arg_version="${OPTARG:-}" ;;
		username ) arg_username="${OPTARG:-}" ;;
		userpass ) arg_userpass="${OPTARG:-}" ;;
		local_image ) arg_local_image="${OPTARG:-}" ;;
		registry ) arg_registry="${OPTARG:-}" ;;
		full_image_name ) arg_full_image_name="${OPTARG:-}" ;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"container:image:tag:exists")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:container:image:tag:exists" ${args[@]+"${args[@]}"}
		;;
	"inner:container:image:tag:exists")
		result="$(curl --fail --silent --show-error -H "Content-Type: application/json" -X POST \
			-d '{"username": "'"${arg_username}"'", "password": "'"${arg_userpass}"'"}' \
			"${arg_registry_api_base_url}/users/login/")"

		token="$(echo "$result" | jq -r .token)"

		result="$(curl --fail --silent --show-error -H "Authorization: JWT ${token}" \
			"${arg_registry_api_base_url}/repositories/${arg_repository}/tags/?page_size=10000")"

		exists="$(echo "$result" | jq -r "[.results | .[] | .name == \"${arg_version}\"] | any")"

		if [ "$exists" = "true" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"container:image:push")
		registry="${arg_registry_host:-}"

		if [ -n "${arg_registry_host:-}" ] \
		&& [ -n "${arg_registry_port:-}" ] \
		&& [ "${arg_registry_port:-}" != '80' ] \
		&& [ "${arg_registry_port:-}" != '443' ]; then
			registry="$registry:$arg_registry_port"
		fi

		full_image_name="$arg_repository:$arg_version"

		if [ -n "$registry" ]; then
			full_image_name="$registry:$full_image_name"
		fi

		>&2 "$pod_script_env_file" "run:container:image:push:$arg_container_type" \
			--local_image="$arg_local_image" \
			--username="$arg_username" \
			--userpass="$arg_userpass" \
			--registry="$registry" \
			--full_image_name="$full_image_name" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$arg_subtask_cmd" \

		;;
	"container:image:push:"*)
		cli="${command#container:image:push:}"
		registry_args=()

		if [ -n "${arg_registry:-}" ]; then
			registry_args=( "$arg_registry" )
		fi

		>&2 "$cli" login --username "$arg_username" --password "$arg_userpass" \
			${registry_args[@]+"${registry_args[@]}"}
		>&2 "$cli" tag "$arg_local_image" "$arg_full_image_name"
		>&2 "$cli" push "$arg_full_image_name"
		;;
	*)
		error "$command: Invalid command"
		;;
esac