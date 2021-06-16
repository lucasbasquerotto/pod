#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

pod_script_mysql_file="$pod_layer_dir/shared/scripts/services/mysql.sh"
pod_script_mongo_file="$pod_layer_dir/shared/scripts/services/mongo.sh"
pod_script_postgres_file="$pod_layer_dir/shared/scripts/services/postgres.sh"
pod_script_elasticsearch_file="$pod_layer_dir/shared/scripts/services/elasticsearch.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

db_common_param_names=()
db_common_param_names+=( "db_task_base_dir" )
db_common_param_names+=( "db_file_name" )
db_common_param_names+=( "snapshot_type" )
db_common_param_names+=( "repository_name" )
db_common_param_names+=( "snapshot_name" )
db_common_param_names+=( "bucket_name" )
db_common_param_names+=( "bucket_path" )
db_common_param_names+=( "db_args" )
db_common_param_names+=( "db_index_prefix" )

db_subtask_param_names=()
db_subtask_param_names+=( "db_service" )
db_subtask_param_names+=( "db_cmd" )
db_subtask_param_names+=( "db_name" )
db_subtask_param_names+=( "db_host" )
db_subtask_param_names+=( "db_port" )
db_subtask_param_names+=( "db_user" )
db_subtask_param_names+=( "db_pass" )
db_subtask_param_names+=( "db_tls" )
db_subtask_param_names+=( "db_tls_ca_cert" )
db_subtask_param_names+=( "authentication_database" )
db_subtask_param_names+=( "db_connect_wait_secs" )
db_subtask_param_names+=( "connection_sleep" )

db_common_args=()

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}" ;;
		task_name ) arg_task_name="${OPTARG:-}" ;;
		db_subtask_cmd ) arg_db_subtask_cmd="${OPTARG:-}" ;;
		db_common_prefix ) arg_db_common_prefix="${OPTARG:-}" ;;
		??* )
			for param_name in "${db_common_param_names[@]}"; do
				if [ "${param_name}" = "$OPT" ]; then
					db_common_args+=( "--${OPT}=${OPTARG:-}" )
				fi
			done
			;;
		\? )  ;; ## ignore
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"shared:db:task:"*)
		subtask_name="${command#shared:db:task:}"
		"$pod_script_env_file" "shared:db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="$subtask_name"
		;;
	"shared:db:common")
		prefix="var_task__${arg_task_name}__${arg_db_common_prefix}_"

		param_task_name="${prefix}_task_name"
		task_name="${!param_task_name:-$arg_task_name}"

		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		param_names=( "db_subtask_cmd" )
		param_names+=( "${db_common_param_names[@]}" )

		for param_name in "${param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		"$pod_script_env_file" "db:subtask:$task_name" "${opts[@]}"
		;;
	"db:task:"*)
		task_name="${command#db:task:}"
		prefix="var_task__${task_name}__db_task_"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		param_names=( "db_subtask_cmd" )
		param_names+=( "${db_common_param_names[@]}" )

		for param_name in "${param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask:"*)
		task_name="${command#db:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		param_names=()
		param_names+=( "db_subtask_cmd" )

		for param_name in "${param_names[@]}"; do
			arg_param_name="arg_$param_name"

			if [ -n "${!arg_param_name:-}" ]; then
				opts+=( "--${param_name}=${!arg_param_name:-}" )
			fi
		done

		opts+=( "${db_common_args[@]}" )

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask")
		prefix="var_task__${arg_task_name}__db_subtask_"

		param_toolbox_service="${prefix}_toolbox_service"
		toolbox_service="${!param_toolbox_service:-$var_run__general__toolbox_service}"

		opts=( "--task_info=$title" )

		opts+=( "--toolbox_service=$toolbox_service" )
		opts+=( "${db_common_args[@]}" )

		param_names=( "${db_subtask_param_names[@]}" )

		for param_name in "${param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		"$pod_script_env_file" "$arg_db_subtask_cmd" "${opts[@]}"
		;;
	"db:main:mysql:"*)
		"$pod_script_mysql_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"db:main:mongo:"*)
		"$pod_script_mongo_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"db:main:postgres:"*)
		"$pod_script_postgres_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"db:main:elasticsearch:"*)
		"$pod_script_elasticsearch_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"db:main:prometheus:"*)
		"$pod_script_elasticsearch_file" "$command" ${args[@]+"${args[@]}"}
		;;
	*)
		error "$title: Invalid command"
		;;
esac
