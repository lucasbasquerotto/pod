#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

pod_main_run_file="$pod_layer_dir/main/scripts/main.sh"
pod_script_run_file="$pod_layer_dir/main/scripts/$var_run__general__orchestration.sh"
pod_script_upgrade_file="$pod_layer_dir/main/scripts/upgrade.sh"
pod_script_remote_file="$pod_layer_dir/main/scripts/remote.sh"
pod_script_container_image_file="$pod_layer_dir/main/scripts/container-image.sh"
pod_script_compress_file="$pod_layer_dir/main/scripts/compress.sh"
pod_script_util_file="$pod_layer_dir/main/scripts/util.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function warn {
	"$pod_script_env_file" "util:warn" --warn="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

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
		force ) arg_force="${OPTARG:-}"; [ -z "${OPTARG:-}" ] && arg_force='true';;
		src_dir ) arg_src_dir="${OPTARG:-}";;
		src_file ) arg_src_file="${OPTARG:-}";;
		bg_file ) arg_bg_file="${OPTARG:-}";;
		action_dir ) arg_action_dir="${OPTARG:-}";;
		action_skip_check ) arg_action_skip_check="${OPTARG:-}";;
		status ) arg_status="${OPTARG:-}";;
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
	"up"|"down"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec"|"kill" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"ash"|"zsh"|"bash"|"system:df" \
		|"util:"*|"run:util:"*|"summary:"*)
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
	"up"|"down"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec"|"kill" \
			|"restart"|"logs"|"ps"|"ps-run"|"sh"|"ash"|"zsh"|"bash"|"system:df")
		"$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"local:task:"*)
		task_name="${command#local:task:}"
		"$pod_script_env_file" "main:task:$task_name" \
			--task_info="$title" \
			--local="true"
		;;
	"main:inner:vars")
		{
			# shellcheck disable=SC1090,SC1091
			. "${pod_layer_dir}/vars.sh"
			echo "var_load_main__inner=true";
			echo "var_load_main__data_dir=${var_load_main__data_dir:-}";
			echo "var_load_main__instance_index=${var_load_main__instance_index:-}";
			echo "var_load_main__local=${var_load_main__local:-}";
			echo "var_load_main__pod_type=${var_load_main__pod_type:-}";
			echo "var_load_meta__no_colors=${var_load_meta__no_colors:-}";
			echo "var_load_meta__no_info=${var_load_meta__no_info:-}";
			echo "var_load_meta__no_info_wrap=${var_load_meta__no_info_wrap:-}";
			echo "var_load_meta__no_stacktrace=${var_load_meta__no_stacktrace:-}";
			echo "var_load_meta__no_summary=${var_load_meta__no_summary:-}";
			echo "var_load_script_path=${var_load_script_path:-}";
		} > "$pod_layer_dir/env/vars.inner.sh"
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

			for inner_task_name in "${arr[@]}"; do
				info "[group item task (${task_name})] ${inner_task_name} - start"
				"$pod_script_env_file" "main:task:$inner_task_name" \
					--task_info="$title" \
					--local="${arg_local:-}"
				info "[group item task (${task_name})] ${inner_task_name} - end"
			done
		fi
		;;
	"setup")
		opts=( "--task_info=$title" )
		opts+=( "--local=${arg_local:-}" )
		opts+=( "--setup_task_name=${var_run__tasks__setup:-}" )
		"$pod_script_upgrade_file" "$command" "${opts[@]}"
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
	"setup:verify:"*)
		prefix="var_task__${arg_task_name}__setup_verify_"

		param_setup_dest_dir_to_verify="${prefix}_setup_dest_dir_to_verify"

		opts=( "--task_info=$title" )
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--setup_dest_dir_to_verify=${!param_setup_dest_dir_to_verify}" )

		"$pod_script_upgrade_file" "$command" "${opts[@]}"
		;;
	"inner:upgrade:"*)
		"$pod_script_upgrade_file" "$command" ${args[@]+"${args[@]}"}
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

		nohup "${pod_script_env_file}" "unique:action:$arg_task_name" \
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
			cmd="unique:cmd"
			[ "${arg_force:-}" = 'true' ] && cmd="unique:cmd:force"

			"$pod_script_env_file" "$cmd" \
				"$pod_script_env_file" "action:exec:$arg_task_name" \
				&& status="$?" || status="$?"

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
		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" \
			"$inner_run_file" "inner:action:verify:$arg_task_name" ${args[@]+"${args[@]}"}
		;;
	"inner:action:verify:"*)
		dir="$arg_action_dir"
		file="${dir}/$arg_task_name"
		new_file="${dir}/$arg_task_name.running"

		if [ ! -d "$arg_action_dir" ]; then
			mkdir -p "$arg_action_dir"
		fi

		if [ -f "$new_file" ]; then
			echo "false"
		elif [ "${arg_action_skip_check:-}" = "true" ] || [ -f "$file" ]; then
			echo "$$" >> "$new_file"

			if [ "${arg_action_skip_check:-}" != "true" ]; then
				>&2 rm -f "$file"
			fi

			pid="$(head -n 1 "$new_file")"

			if [ "$pid" = "$$" ]; then
				echo "true"
			else
				echo "false"
			fi
		else
			echo "false"
		fi
		;;
	"action:remove:"*)
		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" \
			"$inner_run_file" "inner:action:remove:$arg_task_name" ${args[@]+"${args[@]}"}
		;;
	"inner:action:remove:"*)
		dir="$arg_action_dir"
		file="${dir}/$arg_task_name.running"
		error_file="${dir}/$arg_task_name.error"
		done_file="${dir}/$arg_task_name.done"
		result_file="$done_file"

		if [ -f "$file" ]; then
			if [ "${arg_status:-}" != "0" ]; then
				result_file="$error_file"
			fi

			date '+%F %T' > "$result_file"
			rm -f "$file"
		fi

		if [ "${arg_status:-}" != "0" ]; then
			error "$command exited with status ${arg_status:-}"
		fi
		;;
	"unique:all"|"unique:all:force")
		cmd="unique:cmd"
		[ "$command" = "unique:all:force" ] && cmd="unique:cmd:force"

		info "$command - run the following actions: ${args[*]}"

		for action in "${args[@]}"; do
			"$pod_script_env_file" "$cmd" "$pod_script_env_file" "unique:action:$action" \
				|| error "$title: error when running the action: $action" ||:
		done
		;;
	"unique:action:"*)
		task_name="${command#unique:action:}"

		cmd="unique:cmd"
		[ "${arg_force:-}" = 'true' ] && cmd="unique:cmd:force"

		"$pod_script_env_file" "$cmd" "$pod_script_env_file" "action:exec:$task_name"
		;;
	"unique:cmd")
		info "$command: run-one ${args[*]}"
		run-one "${args[@]}" || error "$title"
		;;
	"unique:cmd:force")
		info "$command: run-this-one ${args[*]}"
		run-this-one "${args[@]}" || error "$title"
		;;
	"run:container:image:"*|"inner:container:image:"*)
		run_cmd="${command#run:}"
		"$pod_script_container_image_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"run:compress:"*|"inner:compress:"*|"run:uncompress:"*|"inner:uncompress:"*)
		run_cmd="${command#run:}"
		"$pod_script_compress_file" "$run_cmd" \
			--toolbox_service="$var_run__general__toolbox_service" \
			${args[@]+"${args[@]}"}
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
	"util:"*|"run:util:"*|"inner:util:"*)
		run_cmd="${command#run:}"
		"$pod_script_util_file" "$run_cmd" \
			--toolbox_service="$var_run__general__toolbox_service" \
			${args[@]+"${args[@]}"}
		;;
	"summary:"*)
		run_cmd="${command#summary:}"
		"$pod_script_env_file" "util:info:start" --title="$title"

		"$pod_script_env_file" "$run_cmd"

		"$pod_script_env_file" "util:info:end" --title="$title"

		end_cmd="$(date '+%F %T')"
		"$pod_script_env_file" "util:info:summary" --title="$title" --start="$start" --end="$end_cmd"
		;;
	*)
		error "$command: invalid command"
		;;
esac

end="$(date '+%F %T')"

case "$command" in
	"up"|"down"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec"|"kill" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"ash"|"zsh"|"bash"|"system:df" \
		|"util:"*|"run:util:"*|"summary:"*)
		;;
	*)
		"$pod_script_env_file" "util:info:end" --title="$title"
		"$pod_script_env_file" "util:info:summary" --title="$title" --start="$start" --end="$end"
		;;
esac
