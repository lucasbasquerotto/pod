#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

pod_main_run_file="$pod_layer_dir/main/scripts/main.sh"
pod_script_run_file="$pod_layer_dir/main/scripts/$var_run__general__orchestration.sh"
pod_script_container_file="$pod_layer_dir/main/scripts/container.sh"
pod_script_upgrade_file="$pod_layer_dir/main/scripts/upgrade.sh"
pod_script_db_file="$pod_layer_dir/main/scripts/db.sh"
pod_script_remote_file="$pod_layer_dir/main/scripts/remote.sh"
pod_script_s3_file="$pod_layer_dir/main/scripts/s3.sh"
pod_script_container_image_file="$pod_layer_dir/main/scripts/container-image.sh"
pod_script_certbot_file="$pod_layer_dir/main/scripts/certbot.sh"
pod_script_compress_file="$pod_layer_dir/main/scripts/compress.sh"
pod_script_util_file="$pod_layer_dir/main/scripts/util.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function warn {
	"$pod_script_env_file" "util:warn" --warn="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

function info_inner {
	info "${@}" 2>&1
}

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	error "This project must not be in the '/' directory"
fi

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (main)."
fi

shift;

inner_cmd=''

case "$command" in
	"u")
		command="env"
		inner_cmd="upgrade"
		;;
	"f")
		command="env"
		inner_cmd="fast-upgrade"
		;;
esac

args=("$@")

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then    # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"      # extract long option name
		OPTARG="${OPTARG#$OPT}"  # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"     # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		task_name ) arg_task_name="${OPTARG:-}";;
		local ) arg_local="${OPTARG:-}";;
		src_dir ) arg_src_dir="${OPTARG:-}";;
		src_file ) arg_src_file="${OPTARG:-}";;
		s3_alias ) arg_s3_alias="${OPTARG:-}";;
		s3_cmd ) arg_s3_cmd="${OPTARG:-}";;
		s3_src_alias ) arg_s3_src_alias="${OPTARG:-}";;
		s3_bucket_src_name ) arg_s3_bucket_src_name="${OPTARG:-}";;
		s3_bucket_src_path ) arg_s3_bucket_src_path="${OPTARG:-}";;
		s3_src ) arg_s3_src="${OPTARG:-}";;
		s3_src_rel ) arg_s3_src_rel="${OPTARG:-}";;
		s3_remote_src ) arg_s3_remote_src="${OPTARG:-}";;
		s3_dest_alias ) arg_s3_dest_alias="${OPTARG:-}";;
		s3_bucket_dest_name ) arg_s3_bucket_dest_name="${OPTARG:-}";;
		s3_bucket_dest_path ) arg_s3_bucket_dest_path="${OPTARG:-}";;
		s3_dest ) arg_s3_dest="${OPTARG:-}";;
		s3_dest_rel ) arg_s3_dest_rel="${OPTARG:-}";;
		s3_remote_dest ) arg_s3_remote_dest="${OPTARG:-}";;
		s3_bucket_path ) arg_s3_bucket_path="${OPTARG:-}";;
		s3_older_than_days ) arg_s3_older_than_days="${OPTARG:-}";;
		s3_file ) arg_s3_file="${OPTARG:-}";;
		s3_ignore_path ) arg_s3_ignore_path="${OPTARG:-}";;
		db_subtask_cmd ) arg_db_subtask_cmd="${OPTARG:-}";;
		certbot_cmd ) arg_certbot_cmd="${OPTARG:-}";;
		bg_file ) arg_bg_file="${OPTARG:-}";;
		action_dir ) arg_action_dir="${OPTARG:-}";;
		action_skip_check ) arg_action_skip_check="${OPTARG:-}";;
		status ) arg_status="${OPTARG:-}";;
		db_common_prefix ) arg_db_common_prefix="${OPTARG:-}";;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}";;
		db_file_name ) arg_db_file_name="${OPTARG:-}";;
		snapshot_type ) arg_snapshot_type="${OPTARG:-}";;
		repository_name ) arg_repository_name="${OPTARG:-}";;
		snapshot_name ) arg_snapshot_name="${OPTARG:-}";;
		bucket_name ) arg_bucket_name="${OPTARG:-}" ;;
		bucket_path ) arg_bucket_path="${OPTARG:-}" ;;
		db_args ) arg_db_args="${OPTARG:-}";;
		db_index_prefix ) arg_db_index_prefix="${OPTARG:-}";;
		??* ) ;; ## ignore
		\? )  ;; ## ignore
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

start="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash"|"system:df" \
		|"util:"*|"run:util:"*)
		;;
	*)
		"$pod_script_env_file" "util:info:start" --title="$title"
		;;
esac

case "$command" in
	"env")
		"$pod_script_env_file" "$inner_cmd" ${args[@]+"${args[@]}"}
		;;
	"upgrade"|"fast-upgrade")
		"$pod_script_upgrade_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"stop-to-upgrade")
		"$pod_script_env_file" stop ${args[@]+"${args[@]}"}
		;;
	"prepare")
		>&2 info "$command - do nothing..."
		;;
	"migrate")
		>&2 info "$command - do nothing..."
		;;
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash"|"system:df")

		if [ -n "${var_orchestration__main_file:-}" ] && [ -z "${ORCHESTRATION_MAIN_FILE:-}" ]; then
			export ORCHESTRATION_MAIN_FILE="$var_orchestration__main_file"
		fi

		if [ -n "${var_orchestration__run_file:-}" ] && [ -z "${ORCHESTRATION_RUN_FILE:-}" ]; then
			export ORCHESTRATION_RUN_FILE="$var_orchestration__run_file"
		fi

		"$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"local:task:"*)
		task_name="${command#local:task:}"
		"$pod_script_env_file" "main:task:$task_name" \
			--task_info="$title" \
			--local="true"
		;;
	"main:task:"*)
		task_name="${command#main:task:}"
		prefix="var_task__${task_name}__task_"

		param_type="${prefix}_type"

		"$pod_script_env_file" "${!param_type}:task:$task_name" \
			--task_info="$title" \
			--local="${arg_local:-}"
		;;
	"custom:task:"*)
		task_name="${command#custom:task:}"
		prefix="var_task__${task_name}__custom_task_"

		param_task="${prefix}_task"

		"$pod_script_env_file" "${!param_task}" \
			--task_info="$title" \
			--local="${arg_local:-}"
		;;
	"group:task:"*)
		task_name="${command#group:task:}"
		prefix="var_task__${task_name}__group_task_"

		param_task_names="${prefix}_task_names"

		task_names_values="${!param_task_names:-}"

		info "[$task_name] group tasks: $task_names_values"

		if [ -n "$task_names_values" ]; then
			IFS=',' read -r -a tmp <<< "$task_names_values"
			arr=("${tmp[@]}")

			for task_name in "${arr[@]}"; do
				"$pod_script_env_file" "main:task:$task_name" \
					--task_info="$title" \
					--local="${arg_local:-}"
			done
		fi
		;;
	"setup")
		opts=( "--task_info=$title" )
		opts+=( "--local=${arg_local:-}" )
		opts+=( "--setup_task_name=${var_run__tasks__setup:-}" )
		"$pod_script_upgrade_file" "$command" "${opts[@]}"
		;;
	"setup:main:network")
		default_name="${var_run__general__ctx_full_name}-network"
		network_name="${var_run__general__shared_network:-$default_name}"
		network_result="$("$pod_script_container_file" network ls --format "{{.Name}}" | grep "^${network_name}$" ||:)"

		if [ -z "$network_result" ]; then
			>&2 info "$command - creating the network $network_name..."
			"$pod_script_container_file" network create -d bridge "$network_name"
		fi
		;;
	"setup:task:"*)
		task_name="${command#setup:task:}"
		prefix="var_task__${task_name}__setup_task_"

		param_verify_file_to_skip="${prefix}_verify_file_to_skip"
		param_subtask_cmd_verify="${prefix}_subtask_cmd_verify"
		param_subtask_cmd_remote="${prefix}_subtask_cmd_remote"
		param_subtask_cmd_local="${prefix}_subtask_cmd_local"
		param_subtask_cmd_new="${prefix}_subtask_cmd_new"
		param_setup_run_new_task="${prefix}_setup_run_new_task"
		param_is_compressed_file="${prefix}_is_compressed_file"
		param_compress_type="${prefix}_compress_type"
		param_compress_src_file="${prefix}_compress_src_file"
		param_compress_src_dir="${prefix}_compress_src_dir"
		param_compress_dest_file="${prefix}_compress_dest_file"
		param_compress_dest_dir="${prefix}_compress_dest_dir"
		param_compress_flat="${prefix}_compress_flat"
		param_compress_pass="${prefix}_compress_pass"
		param_recursive_dir="${prefix}_recursive_dir"
		param_recursive_mode="${prefix}_recursive_mode"
		param_recursive_mode_dir="${prefix}_recursive_mode_dir"
		param_recursive_mode_file="${prefix}_recursive_mode_file"
		param_move_src="${prefix}_move_src"
		param_move_dest="${prefix}_move_dest"
		param_file_to_clear="${prefix}_file_to_clear"
		param_dir_to_clear="${prefix}_dir_to_clear"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--local=${arg_local:-}" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--verify_file_to_skip=${!param_verify_file_to_skip:-}" )
		opts+=( "--subtask_cmd_verify=${!param_subtask_cmd_verify:-}" )
		opts+=( "--subtask_cmd_remote=${!param_subtask_cmd_remote:-}" )
		opts+=( "--subtask_cmd_local=${!param_subtask_cmd_local:-}" )
		opts+=( "--subtask_cmd_new=${!param_subtask_cmd_new:-}" )
		opts+=( "--setup_run_new_task=${!param_setup_run_new_task:-}" )
		opts+=( "--is_compressed_file=${!param_is_compressed_file:-}" )
		opts+=( "--compress_type=${!param_compress_type:-}" )
		opts+=( "--compress_src_file=${!param_compress_src_file:-}" )
		opts+=( "--compress_src_dir=${!param_compress_src_dir:-}" )
		opts+=( "--compress_dest_file=${!param_compress_dest_file:-}" )
		opts+=( "--compress_dest_dir=${!param_compress_dest_dir:-}" )
		opts+=( "--compress_flat=${!param_compress_flat:-}" )
		opts+=( "--compress_pass=${!param_compress_pass:-}" )
		opts+=( "--recursive_dir=${!param_recursive_dir:-}" )
		opts+=( "--recursive_mode=${!param_recursive_mode:-}" )
		opts+=( "--recursive_mode_dir=${!param_recursive_mode_dir:-}" )
		opts+=( "--recursive_mode_file=${!param_recursive_mode_file:-}" )
		opts+=( "--move_src=${!param_move_src:-}" )
		opts+=( "--move_dest=${!param_move_dest:-}" )
		opts+=( "--file_to_clear=${!param_file_to_clear:-}" )
		opts+=( "--dir_to_clear=${!param_dir_to_clear:-}" )

		"$pod_script_upgrade_file" "setup:default" "${opts[@]}"
		;;
	"setup:verify:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_verify"
		;;
	"setup:local:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_local"
		;;
	"setup:remote:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_remote"
		;;
	"setup:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_db"
		;;
	"setup:verify:default")
		prefix="var_task__${arg_task_name}__setup_verify_"

		param_setup_dest_dir_to_verify="${prefix}_setup_dest_dir_to_verify"

		opts=( "--task_info=$title" )
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--setup_dest_dir_to_verify=${!param_setup_dest_dir_to_verify}" )

		"$pod_script_upgrade_file" "setup:verify" "${opts[@]}"
		;;
	"setup:remote:default")
		prefix="var_task__${arg_task_name}__setup_remote_"

		param_subtask_cmd_s3="${prefix}_subtask_cmd_s3"
		param_restore_use_s3="${prefix}_restore_use_s3"
		param_restore_s3_sync="${prefix}_restore_s3_sync"
		param_restore_dest_dir="${prefix}_restore_dest_dir"
		param_restore_dest_file="${prefix}_restore_dest_file"
		param_restore_remote_file="${prefix}_restore_remote_file"
		param_restore_bucket_path_dir="${prefix}_restore_bucket_path_dir"
		param_restore_bucket_path_file="${prefix}_restore_bucket_path_file"

		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--subtask_cmd_s3=${!param_subtask_cmd_s3:-}" )
		opts+=( "--restore_use_s3=${!param_restore_use_s3:-}" )
		opts+=( "--restore_s3_sync=${!param_restore_s3_sync:-}" )
		opts+=( "--restore_dest_dir=${!param_restore_dest_dir:-}" )
		opts+=( "--restore_dest_file=${!param_restore_dest_file:-}" )
		opts+=( "--restore_remote_file=${!param_restore_remote_file:-}" )
		opts+=( "--restore_bucket_path_dir=${!param_restore_bucket_path_dir:-}" )
		opts+=( "--restore_bucket_path_file=${!param_restore_bucket_path_file:-}" )

		"$pod_script_remote_file" restore "${opts[@]}"
		;;
	"local.backup")
		"$pod_main_run_file" backup --task_info="$title" --local="true"
		;;
	"backup")
		opts=( "--task_info=$title" )

		opts+=( "--local=${arg_local:-}" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--backup_task_name=$var_run__tasks__backup" )
		opts+=( "--backup_is_delete_old=$var_run__general__backup_is_delete_old" )

		"$pod_script_upgrade_file" backup "${opts[@]}"
		;;
	"backup:task:"*)
		task_name="${command#backup:task:}"
		prefix="var_task__${task_name}__backup_task_"

		param_verify_file_to_skip="${prefix}_verify_file_to_skip"
		param_subtask_cmd_verify="${prefix}_subtask_cmd_verify"
		param_subtask_cmd_remote="${prefix}_subtask_cmd_remote"
		param_subtask_cmd_local="${prefix}_subtask_cmd_local"
		param_no_src_needed="${prefix}_no_src_needed"
		param_backup_src="${prefix}_backup_src"
		param_backup_date_format="${prefix}_backup_date_format"
		param_backup_time_format="${prefix}_backup_time_format"
		param_backup_datetime_format="${prefix}_backup_datetime_format"
		param_is_compressed_file="${prefix}_is_compressed_file"
		param_compress_type="${prefix}_compress_type"
		param_compress_dest_file="${prefix}_compress_dest_file"
		param_compress_dest_dir="${prefix}_compress_dest_dir"
		param_compress_flat="${prefix}_compress_flat"
		param_compress_pass="${prefix}_compress_pass"
		param_recursive_dir="${prefix}_recursive_dir"
		param_recursive_mode="${prefix}_recursive_mode"
		param_recursive_mode_dir="${prefix}_recursive_mode_dir"
		param_recursive_mode_file="${prefix}_recursive_mode_file"
		param_file_to_clear="${prefix}_file_to_clear"
		param_dir_to_clear="${prefix}_dir_to_clear"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--local=${arg_local:-}" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--verify_file_to_skip=${!param_verify_file_to_skip:-}" )
		opts+=( "--subtask_cmd_verify=${!param_subtask_cmd_verify:-}" )
		opts+=( "--subtask_cmd_remote=${!param_subtask_cmd_remote:-}" )
		opts+=( "--subtask_cmd_local=${!param_subtask_cmd_local:-}" )
		opts+=( "--backup_no_src_needed=${!param_no_src_needed:-}" )
		opts+=( "--backup_src=${!param_backup_src:-}" )
		opts+=( "--backup_date_format=${!param_backup_date_format:-}" )
		opts+=( "--backup_time_format=${!param_backup_time_format:-}" )
		opts+=( "--backup_datetime_format=${!param_backup_datetime_format:-}" )
		opts+=( "--is_compressed_file=${!param_is_compressed_file:-}" )
		opts+=( "--compress_type=${!param_compress_type:-}" )
		opts+=( "--compress_dest_file=${!param_compress_dest_file:-}" )
		opts+=( "--compress_dest_dir=${!param_compress_dest_dir:-}" )
		opts+=( "--compress_flat=${!param_compress_flat:-}" )
		opts+=( "--compress_pass=${!param_compress_pass:-}" )
		opts+=( "--recursive_dir=${!param_recursive_dir:-}" )
		opts+=( "--recursive_mode=${!param_recursive_mode:-}" )
		opts+=( "--recursive_mode_dir=${!param_recursive_mode_dir:-}" )
		opts+=( "--recursive_mode_file=${!param_recursive_mode_file:-}" )
		opts+=( "--file_to_clear=${!param_file_to_clear:-}" )
		opts+=( "--dir_to_clear=${!param_dir_to_clear:-}" )

		"$pod_script_upgrade_file" "backup:default" "${opts[@]}"
		;;
	"backup:remote:default")
		prefix="var_task__${arg_task_name}__backup_remote_"

		param_subtask_cmd_s3="${prefix}_subtask_cmd_s3"
		param_backup_src_dir="${prefix}_backup_src_dir"
		param_backup_src_file="${prefix}_backup_src_file"
		param_backup_ignore_path="${prefix}_backup_ignore_path"
		param_backup_bucket_sync_dir="${prefix}_backup_bucket_sync_dir"
		param_backup_date_format="${prefix}_backup_date_format"
		param_backup_time_format="${prefix}_backup_time_format"
		param_backup_datetime_format="${prefix}_backup_datetime_format"

		backup_src_dir="${!param_backup_src_dir:-}"
		backup_src_file="${!param_backup_src_file:-}"

		backup_src_dir="${arg_src_dir:-$backup_src_dir}"
		backup_src_file="${arg_src_file:-$backup_src_file}"

		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--subtask_cmd_s3=${!param_subtask_cmd_s3:-}" )
		opts+=( "--backup_src_dir=$backup_src_dir" )
		opts+=( "--backup_src_file=$backup_src_file" )
		opts+=( "--backup_bucket_sync_dir=${!param_backup_bucket_sync_dir:-}" )
		opts+=( "--backup_ignore_path=${!param_backup_ignore_path:-}" )
		opts+=( "--backup_date_format=${!param_backup_date_format:-}" )
		opts+=( "--backup_time_format=${!param_backup_time_format:-}" )
		opts+=( "--backup_datetime_format=${!param_backup_datetime_format:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
		;;
	"backup:local:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_local"
		;;
	"backup:remote:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_remote"
		;;
	"backup:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_db"
		;;
	"db:common")
		prefix="var_task__${arg_task_name}__${arg_db_common_prefix}_"

		param_task_name="${prefix}_task_name"
		param_db_subtask_cmd="${prefix}_db_subtask_cmd"
		param_db_task_base_dir="${prefix}_db_task_base_dir"
		param_db_file_name="${prefix}_db_file_name"
		param_snapshot_type="${prefix}_snapshot_type"
		param_repository_name="${prefix}_repository_name"
		param_snapshot_name="${prefix}_snapshot_name"
		param_bucket_name="${prefix}_bucket_name"
		param_bucket_path="${prefix}_bucket_path"
		param_db_args="${prefix}_db_args"
		param_db_index_prefix="${prefix}_db_index_prefix"

		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${!param_db_subtask_cmd}" )
		opts+=( "--db_task_base_dir=${!param_db_task_base_dir:-}" )
		opts+=( "--db_file_name=${!param_db_file_name:-}" )
		opts+=( "--snapshot_type=${!param_snapshot_type:-}" )
		opts+=( "--repository_name=${!param_repository_name:-}" )
		opts+=( "--snapshot_name=${!param_snapshot_name:-}" )
		opts+=( "--bucket_name=${!param_bucket_name:-}" )
		opts+=( "--bucket_path=${!param_bucket_path:-}" )
		opts+=( "--db_args=${!param_db_args:-}" )
		opts+=( "--db_index_prefix=${!param_db_index_prefix:-}" )

		"$pod_script_env_file" "db:subtask:${!param_task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"db:task:"*)
		task_name="${command#db:task:}"
		prefix="var_task__${task_name}__db_task_"

		param_db_subtask_cmd="${prefix}_db_subtask_cmd"
		param_db_task_base_dir="${prefix}_db_task_base_dir"
		param_db_file_name="${prefix}_db_file_name"
		param_snapshot_type="${prefix}_snapshot_type"
		param_repository_name="${prefix}_repository_name"
		param_snapshot_name="${prefix}_snapshot_name"
		param_bucket_name="${prefix}_bucket_name"
		param_bucket_path="${prefix}_bucket_path"
		param_db_args="${prefix}_db_args"
		param_db_index_prefix="${prefix}_db_index_prefix"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${!param_db_subtask_cmd:-}" )
		opts+=( "--db_task_base_dir=${!param_db_task_base_dir:-}" )
		opts+=( "--db_file_name=${!param_db_file_name:-}" )
		opts+=( "--snapshot_type=${!param_snapshot_type:-}" )
		opts+=( "--repository_name=${!param_repository_name:-}" )
		opts+=( "--snapshot_name=${!param_snapshot_name:-}" )
		opts+=( "--bucket_name=${!param_bucket_name:-}" )
		opts+=( "--bucket_path=${!param_bucket_path:-}" )
		opts+=( "--db_args=${!param_db_args:-}" )
		opts+=( "--db_index_prefix=${!param_db_index_prefix:-}" )

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask:"*)
		task_name="${command#db:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${arg_db_subtask_cmd:-}" )
		opts+=( "--db_task_base_dir=${arg_db_task_base_dir:-}" )
		opts+=( "--db_file_name=${arg_db_file_name:-}" )
		opts+=( "--snapshot_type=${arg_snapshot_type:-}" )
		opts+=( "--repository_name=${arg_repository_name:-}" )
		opts+=( "--snapshot_name=${arg_snapshot_name:-}" )
		opts+=( "--bucket_name=${arg_bucket_name:-}" )
		opts+=( "--bucket_path=${arg_bucket_path:-}" )
		opts+=( "--db_args=${arg_db_args:-}" )
		opts+=( "--db_index_prefix=${arg_db_index_prefix:-}" )

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask")
		prefix="var_task__${arg_task_name}__db_subtask_"

		param_toolbox_service="${prefix}_toolbox_service"
		param_db_service="${prefix}_db_service"
		param_db_cmd="${prefix}_db_cmd"
		param_db_name="${prefix}_db_name"
		param_db_host="${prefix}_db_host"
		param_db_port="${prefix}_db_port"
		param_db_user="${prefix}_db_user"
		param_db_pass="${prefix}_db_pass"
		param_authentication_database="${prefix}_authentication_database"
		param_db_connect_wait_secs="${prefix}_db_connect_wait_secs"
		param_connection_sleep="${prefix}_connection_sleep"

		opts=( "--task_info=$title" )

		opts+=( "--db_task_base_dir=${arg_db_task_base_dir:-}" )
		opts+=( "--db_file_name=${arg_db_file_name:-}" )
		opts+=( "--snapshot_type=${arg_snapshot_type:-}" )
		opts+=( "--repository_name=${arg_repository_name:-}" )
		opts+=( "--snapshot_name=${arg_snapshot_name:-}" )
		opts+=( "--bucket_name=${arg_bucket_name:-}" )
		opts+=( "--bucket_path=${arg_bucket_path:-}" )
		opts+=( "--db_args=${arg_db_args:-}" )
		opts+=( "--db_index_prefix=${arg_db_index_prefix:-}" )

		opts+=( "--toolbox_service=${!param_toolbox_service:-$var_run__general__toolbox_service}" )
		opts+=( "--db_service=${!param_db_service:-}" )
		opts+=( "--db_cmd=${!param_db_cmd:-}" )
		opts+=( "--db_name=${!param_db_name:-}" )
		opts+=( "--db_host=${!param_db_host:-}" )
		opts+=( "--db_port=${!param_db_port:-}" )
		opts+=( "--db_user=${!param_db_user:-}" )
		opts+=( "--db_pass=${!param_db_pass:-}" )
		opts+=( "--authentication_database=${!param_authentication_database:-}" )
		opts+=( "--db_connect_wait_secs=${!param_db_connect_wait_secs:-}" )
		opts+=( "--connection_sleep=${!param_connection_sleep:-}" )

		"$pod_script_db_file" "$arg_db_subtask_cmd" "${opts[@]}"
		;;
	"run:db:"*)
		run_cmd="${command#run:}"
		"$pod_script_db_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"s3:task:"*)
		task_name="${command#s3:task:}"
		prefix="var_task__${task_name}__s3_task_"

		param_s3_alias="${prefix}_s3_alias"
		param_s3_cmd="${prefix}_s3_cmd"
		param_s3_src_alias="${prefix}_s3_src_alias"
		param_s3_bucket_src_name="${prefix}_s3_bucket_src_name"
		param_s3_bucket_src_path="${prefix}_s3_bucket_src_path"
		param_s3_src="${prefix}_s3_src"
		param_s3_remote_src="${prefix}_s3_remote_src"
		param_s3_src_rel="${prefix}_s3_src_rel"
		param_s3_dest_alias="${prefix}_s3_dest_alias"
		param_s3_bucket_dest_name="${prefix}_s3_bucket_dest_name"
		param_s3_bucket_dest_path="${prefix}_s3_bucket_dest_path"
		param_s3_dest="${prefix}_s3_dest"
		param_s3_remote_dest="${prefix}_s3_remote_dest"
		param_s3_dest_rel="${prefix}_s3_dest_rel"
		param_s3_bucket_path="${prefix}_s3_bucket_path"
		param_s3_older_than_days="${prefix}_s3_older_than_days"
		param_s3_file="${prefix}_s3_file"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--s3_alias=${!param_s3_alias:-}" )
		opts+=( "--s3_cmd=${!param_s3_cmd:-}" )
		opts+=( "--s3_src_alias=${!param_s3_src_alias:-}" )
		opts+=( "--s3_bucket_src_name=${!param_s3_bucket_src_name:-}" )
		opts+=( "--s3_bucket_src_path=${!param_s3_bucket_src_path:-}" )
		opts+=( "--s3_src=${!param_s3_src:-}" )
		opts+=( "--s3_remote_src=${!param_s3_remote_src:-}" )
		opts+=( "--s3_src_rel=${!param_s3_src_rel:-}" )
		opts+=( "--s3_dest_alias=${!param_s3_dest_alias:-}" )
		opts+=( "--s3_bucket_dest_name=${!param_s3_bucket_dest_name:-}" )
		opts+=( "--s3_bucket_dest_path=${!param_s3_bucket_dest_path:-}" )
		opts+=( "--s3_dest=${!param_s3_dest:-}" )
		opts+=( "--s3_remote_dest=${!param_s3_remote_dest:-}" )
		opts+=( "--s3_dest_rel=${!param_s3_dest_rel:-}" )
		opts+=( "--s3_bucket_path=${!param_s3_bucket_path:-}" )
		opts+=( "--s3_older_than_days=${!param_s3_older_than_days:-}" )
		opts+=( "--s3_file=${!param_s3_file:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask:"*)
		task_name="${command#s3:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--s3_alias=${arg_s3_alias:-}" )
		opts+=( "--s3_cmd=${arg_s3_cmd:-}" )
		opts+=( "--s3_src_alias=${arg_s3_src_alias:-}" )
		opts+=( "--s3_bucket_src_name=${arg_s3_bucket_src_name:-}" )
		opts+=( "--s3_bucket_src_path=${arg_s3_bucket_src_path:-}" )
		opts+=( "--s3_src=${arg_s3_src:-}" )
		opts+=( "--s3_remote_src=${arg_s3_remote_src:-}" )
		opts+=( "--s3_src_rel=${arg_s3_src_rel:-}" )
		opts+=( "--s3_dest_alias=${arg_s3_dest_alias:-}" )
		opts+=( "--s3_bucket_dest_name=${arg_s3_bucket_dest_name:-}" )
		opts+=( "--s3_bucket_dest_path=${arg_s3_bucket_dest_path:-}" )
		opts+=( "--s3_dest=${arg_s3_dest:-}" )
		opts+=( "--s3_remote_dest=${arg_s3_remote_dest:-}" )
		opts+=( "--s3_dest_rel=${arg_s3_dest_rel:-}" )
		opts+=( "--s3_bucket_path=${arg_s3_bucket_path:-}" )
		opts+=( "--s3_older_than_days=${arg_s3_older_than_days:-}" )
		opts+=( "--s3_file=${arg_s3_file:-}" )
		opts+=( "--s3_ignore_path=${arg_s3_ignore_path:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask")
		prefix="var_task__${arg_task_name}__s3_subtask_"

		param_cli="${prefix}_cli"
		param_cli_cmd="${prefix}_cli_cmd"
		param_service="${prefix}_service"
		param_tmp_dir="${prefix}_tmp_dir"
		param_alias="${prefix}_alias"
		param_endpoint="${prefix}_endpoint"
		param_bucket_name="${prefix}_bucket_name"
		param_bucket_path="${prefix}_bucket_path"
		param_bucket_src_name="${prefix}_bucket_src_name"
		param_bucket_src_path="${prefix}_bucket_src_path"
		param_bucket_dest_name="${prefix}_bucket_dest_name"
		param_bucket_dest_path="${prefix}_bucket_dest_path"

		alias="${!param_alias:-}"

		if [ -z "${!param_alias:-}" ]; then
			alias="${arg_s3_alias:-}"
		fi

		bucket_src_name="${!param_bucket_name:-}"
		bucket_src_path="${!param_bucket_path:-}"

		if [ -n "${!param_bucket_src_name:-}" ]; then
			bucket_src_name="${!param_bucket_src_name:-}"
			bucket_src_path="${!param_bucket_src_path:-}"
		fi

		if [ -n "${arg_s3_bucket_src_name:-}" ]; then
			bucket_src_name="${arg_s3_bucket_src_name:-}"
			bucket_src_path="${arg_s3_bucket_src_path:-}"
		fi

		bucket_src_prefix="$bucket_src_name"

		if [ -n "$bucket_src_path" ]; then
			bucket_src_prefix="$bucket_src_name/$bucket_src_path"
		fi

		s3_src="${arg_s3_src:-}"

		if [ "${arg_s3_remote_src:-}" = "true" ]; then
			s3_src="$bucket_src_prefix"

			if [ -n "${arg_s3_src_rel:-}" ];then
				s3_src="$s3_src/$arg_s3_src_rel"
			fi

			s3_src=$(echo "$s3_src" | tr -s /)
		fi

		bucket_dest_name="${!param_bucket_name:-}"
		bucket_dest_path="${!param_bucket_path:-}"

		if [ -n "${!param_bucket_dest_name:-}" ]; then
			bucket_dest_name="${!param_bucket_dest_name:-}"
			bucket_dest_path="${!param_bucket_dest_path:-}"
		fi

		if [ -n "${arg_s3_bucket_dest_name:-}" ]; then
			bucket_dest_name="${arg_s3_bucket_dest_name:-}"
			bucket_dest_path="${arg_s3_bucket_dest_path:-}"
		fi

		bucket_dest_prefix="$bucket_dest_name"

		if [ -n "$bucket_dest_path" ]; then
			bucket_dest_prefix="$bucket_dest_name/$bucket_dest_path"
		fi

		s3_dest="${arg_s3_dest:-}"

		if [ "${arg_s3_remote_dest:-}" = "true" ]; then
			s3_dest="$bucket_dest_prefix"

			if [ -n "${arg_s3_dest_rel:-}" ];then
				s3_dest="$s3_dest/$arg_s3_dest_rel"
			fi

			s3_dest=$(echo "$s3_dest" | tr -s /)
		fi

		bucket_base_prefix="s3://$param_bucket_name"

		if [ -n "${s3_alias:-}" ]; then
			bucket_base_prefix="$s3_alias/$param_bucket_name"
		fi

		s3_path="$bucket_base_prefix"

		if [ -n "${param_bucket_path:-}" ]; then
			s3_path="$bucket_base_prefix/$param_bucket_path"
		fi

		s3_opts=()

		if [ -n "${arg_s3_file:-}" ]; then
			s3_opts+=( --exclude "*" --include "$arg_s3_file" )
		fi
		if [ -n "${arg_s3_ignore_path:-}" ]; then
			s3_opts+=( --exclude "${arg_s3_ignore_path:-}" )
		fi

		opts=( "--task_info=$title" )

		opts+=( "--s3_service=${!param_service:-}" )
		opts+=( "--s3_tmp_dir=${!param_tmp_dir:-}" )
		opts+=( "--s3_alias=$alias" )
		opts+=( "--s3_endpoint=${!param_endpoint:-}" )
		opts+=( "--s3_bucket_name=${!param_bucket_name:-}" )

		opts+=( "--s3_remote_src=${arg_s3_remote_src:-}" )
		opts+=( "--s3_src_alias=${arg_s3_src_alias:-}" )
		opts+=( "--s3_src=${s3_src:-}" )
		opts+=( "--s3_remote_dest=${arg_s3_remote_dest:-}" )
		opts+=( "--s3_dest_alias=${arg_s3_dest_alias:-}" )
		opts+=( "--s3_dest=${s3_dest:-}" )
		opts+=( "--s3_path=${s3_path:-}" )
		opts+=( "--s3_older_than_days=${arg_s3_older_than_days:-}" )
		opts+=( "--s3_opts" )
		opts+=( ${s3_opts[@]+"${s3_opts[@]}"} )

		inner_cmd="s3:${!param_cli}:${!param_cli_cmd}:$arg_s3_cmd"
		info "$command - $inner_cmd"
		"$pod_script_s3_file" "$inner_cmd" "${opts[@]}"
		;;
	"certbot:task:"*)
		task_name="${command#certbot:task:}"
		prefix="var_task__${task_name}__certbot_task_"

		param_certbot_cmd="${prefix}_certbot_cmd"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=${!param_certbot_cmd}" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask:"*)
		task_name="${command#certbot:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=$arg_certbot_cmd" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask")
		prefix="var_task__${arg_task_name}__certbot_subtask_"

		param_toolbox_service="${prefix}_toolbox_service"
		param_certbot_service="${prefix}_certbot_service"
		param_webservice_service="${prefix}_webservice_service"
		param_webservice_type="${prefix}_webservice_type"
		param_data_base_path="${prefix}_data_base_path"
		param_main_domain="${prefix}_main_domain"
		param_domains="${prefix}_domains"
		param_rsa_key_size="${prefix}_rsa_key_size"
		param_email="${prefix}_email"
		param_dev="${prefix}_dev"
		param_dev_renew_days="${prefix}_dev_renew_days"
		param_staging="${prefix}_staging"
		param_force="${prefix}_force"

		webservice_type_value="${!param_webservice_type}"

		opts=( "--task_info=$title" )

		opts+=( "--toolbox_service=${!param_toolbox_service}" )
		opts+=( "--certbot_service=${!param_certbot_service}" )
		opts+=( "--webservice_type=${!param_webservice_type}" )
		opts+=( "--data_base_path=${!param_data_base_path}" )
		opts+=( "--main_domain=${!param_main_domain}" )
		opts+=( "--domains=${!param_domains}" )
		opts+=( "--rsa_key_size=${!param_rsa_key_size}" )
		opts+=( "--email=${!param_email}" )

		opts+=( "--webservice_service=${!param_webservice_service:-$webservice_type_value}" )
		opts+=( "--dev=${!param_dev:-}" )
		opts+=( "--dev_renew_days=${!param_dev_renew_days:-}" )
		opts+=( "--staging=${!param_staging:-}" )
		opts+=( "--force=${!param_force:-}" )

		"$pod_script_certbot_file" "certbot:$arg_certbot_cmd" "${opts[@]}"
		;;
	"run:certbot:"*)
		run_cmd="${command#run:}"
		"$pod_script_certbot_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"verify")
		"$pod_script_env_file" "main:task:$var_run__tasks__verify" \
			--task_info="$title"
		;;
	"verify:db:connection")
		prefix="var_task__${arg_task_name}__verify_db_connection_"

		param_task_name="${prefix}_task_name"
		param_db_subtask_cmd="${prefix}_db_subtask_cmd"

		opts=( "--task_info=$title" )
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${!param_db_subtask_cmd}" )

		"$pod_script_env_file" "db:subtask:${!param_task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"bg:task:"*)
		task_name="${command#bg:task:}"
		prefix="var_task__${task_name}__bg_task_"

		param_bg_file="${prefix}_bg_file"
		param_action_dir="${prefix}_action_dir"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--bg_file=${!param_bg_file}" )
		opts+=( "--action_dir=${!param_action_dir}" )

		"$pod_script_env_file" "action:subtask" "${opts[@]}"
		;;
	"bg:subtask")
		touch "$arg_bg_file"

		nohup "${pod_script_env_file}" "unique:subtask:$arg_task_name" \
			--task_info="$title" \
			--action_dir="$arg_action_dir" \
			>> "$arg_bg_file" 2>&1 &

		pid=$!
		tail --pid="$pid" -n 2 -f "$arg_bg_file"
		wait "$pid" && status=$? || status=$?

		if [[ $status -ne 0 ]]; then
			error "$command:$arg_task_name - exited with status $status"
		fi
		;;
	"action:task:"*)
		task_name="${command#action:task:}"
		prefix="var_task__${task_name}__action_task_"

		param_toolbox_service="${prefix}_toolbox_service"
		param_action_dir="${prefix}_action_dir"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--action_dir=${!param_action_dir}" )

		"$pod_script_env_file" "action:subtask" "${opts[@]}"
		;;
	"action:subtask:"*)
		task_name="${command#action:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--action_dir=$arg_action_dir" )

		"$pod_script_env_file" "action:subtask" "${opts[@]}"
		;;
	"action:subtask")
		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--action_dir=$arg_action_dir" )

		execute="$("$pod_script_env_file" "action:verify:$arg_task_name" "${opts[@]}")" \
			|| error "$command"

		if [ "$execute" = "true" ]; then
			"$pod_script_env_file" "action:exec:$arg_task_name" && status="$?" || status="$?"
			"$pod_script_env_file" "action:remove:$arg_task_name" \
				--status="$status" "${opts[@]}"

			if [ "$status" != "0" ]; then
				error "$command exited with status $status"
			fi
		else
			>&2 echo "skipping..."
		fi
		;;
	"action:verify:"*)
		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			dir="$arg_action_dir"
			file="\${dir}/$arg_task_name"
			new_file="\${dir}/$arg_task_name.running"

			if [ ! -d "$arg_action_dir" ]; then
				mkdir -p "$arg_action_dir"
			fi

			if [ -f "\$new_file" ]; then
				echo "false"
			elif [ "${arg_action_skip_check:-}" = "true" ] || [ -f "\$file" ]; then
				echo "$$" >> "\$new_file"

				if [ "${arg_action_skip_check:-}" != "true" ]; then
					>&2 rm -f "\$file"
				fi

				pid="\$(head -n 1 "\$new_file")"

				if [ "\$pid" = "$$" ]; then
					echo "true"
				else
					echo "false"
				fi
			else
				echo "false"
			fi
		SHELL
		;;
	"action:remove:"*)
		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			dir="$arg_action_dir"
			file="\${dir}/$arg_task_name.running"
			error_file="\${dir}/$arg_task_name.error"

			if [ -f "\$file" ]; then
				if [ "${arg_status:-}" != "0" ]; then
					echo "\$(date '+%F %T')" > "\$error_file"
				fi

				rm -f "\$file"
			fi
		SHELL

		if [ "${arg_status:-}" != "0" ]; then
			error "$command exited with status ${arg_status:-}"
		fi
		;;
	"unique:task:"*)
		task_name="${command#unique:task:}"
		prefix="var_task__${task_name}__unique_task_"

		param_toolbox_service="${prefix}_toolbox_service"
		param_action_dir="${prefix}_action_dir"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=${!param_toolbox_service}" )
		opts+=( "--action_dir=${!param_action_dir}" )

		"$pod_script_env_file" "unique:subtask" "${opts[@]}"
		;;
	"unique:subtask:"*)
		task_name="${command#unique:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--action_dir=$arg_action_dir" )

		"$pod_script_env_file" "unique:subtask" "${opts[@]}"
		;;
	"unique:subtask")
		opts=( "--task_info=$title" )

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--action_dir=$arg_action_dir" )
		opts+=( "--action_skip_check=true" )

		execute="$("$pod_script_env_file" "action:verify:$arg_task_name" "${opts[@]}")" \
			|| error "$command"

		if [ "$execute" = "true" ]; then
			"$pod_script_env_file" "action:exec:$arg_task_name" && status="$?" || status="$?"
			"$pod_script_env_file" "action:remove:$arg_task_name" \
				--status="$status" "${opts[@]}"
		else
			error "$command: process already running"
		fi
		;;
	"run:container:image:"*)
		run_cmd="${command#run:}"
		"$pod_script_container_image_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"run:compress:"*|"run:uncompress:"*)
		run_cmd="${command#run:}"
		"$pod_script_compress_file" "$run_cmd" \
			--toolbox_service="$var_run__general__toolbox_service" \
			${args[@]+"${args[@]}"}
		;;
	"run:s3:"*)
		run_cmd="${command#run:}"
		"$pod_script_s3_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"util:info"|"util:info:"*|"run:util:info:"*| \
	"util:warn"|"util:error")
		run_cmd="${command#run:}"
		"$pod_script_util_file" "$run_cmd" \
			--no_info="${var_run__meta__no_info:-}" \
			--no_warn="${var_run__meta__no_warn:-}" \
			--no_error="${var_run__meta__no_error:-}" \
			--no_info_wrap="${var_run__meta__no_info_wrap:-}" \
			--no_summary="${var_run__meta__no_summary:-}" \
			--no_colors="${var_run__meta__no_colors:-}" \
			${args[@]+"${args[@]}"}
		;;
	"util:"*|"run:util:"*)
		run_cmd="${command#run:}"
		"$pod_script_util_file" "$run_cmd" \
			--toolbox_service="$var_run__general__toolbox_service" \
			${args[@]+"${args[@]}"}
		;;
	*)
		error "$command: invalid command"
		;;
esac

end="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash"|"system:df" \
		|"util:"*|"run:util:"*)
		;;
	*)
		"$pod_script_env_file" "util:info:end" --title="$title"
		"$pod_script_env_file" "util:info:summary" --title="$title" --start="$start" --end="$end"
		;;
esac
