#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

pod_script_awscli_file="$pod_layer_dir/shared/scripts/services/awscli.sh"
pod_script_mc_file="$pod_layer_dir/shared/scripts/services/mc.sh"
pod_script_rclone_file="$pod_layer_dir/shared/scripts/services/rclone.sh"

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

task_param_names=()
task_param_names+=( "alias" )
task_param_names+=( "cmd" )
task_param_names+=( "src_alias" )
task_param_names+=( "bucket_src_name" )
task_param_names+=( "bucket_src_path" )
task_param_names+=( "src" )
task_param_names+=( "remote_src" )
task_param_names+=( "src_rel" )
task_param_names+=( "dest_alias" )
task_param_names+=( "bucket_dest_name" )
task_param_names+=( "bucket_dest_path" )
task_param_names+=( "dest" )
task_param_names+=( "remote_dest" )
task_param_names+=( "dest_rel" )
task_param_names+=( "path" )
task_param_names+=( "bucket_path" )
task_param_names+=( "older_than_days" )
task_param_names+=( "file" )
task_param_names+=( "ignore_path" )
task_param_names+=( "test" )

s3_task_args=()

subtask_param_names=()
subtask_param_names+=( "service" )
subtask_param_names+=( "tmp_dir" )
subtask_param_names+=( "endpoint" )
subtask_param_names+=( "bucket_name" )
subtask_param_names+=( "lifecycle_dir" )
subtask_param_names+=( "lifecycle_file" )
subtask_param_names+=( "acl" )

subtask_args_param_names=()
subtask_args_param_names+=( "remote_src" )
subtask_args_param_names+=( "remote_dest" )
subtask_args_param_names+=( "path" )
subtask_args_param_names+=( "file" )
subtask_args_param_names+=( "ignore_path" )
subtask_args_param_names+=( "older_than_days" )
subtask_args_param_names+=( "test" )

s3_subtask_args=()

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}" ;;
		task_name ) arg_task_name="${OPTARG:-}";;
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
		??* )
			for param_name in "${task_param_names[@]}"; do
				if [ "s3_${param_name}" = "$OPT" ]; then
					s3_task_args+=( "--${OPT}=${OPTARG:-}" )
				fi
			done
			for param_name in "${subtask_args_param_names[@]}"; do
				if [ "s3_${param_name}" = "$OPT" ]; then
					s3_subtask_args+=( "--${OPT}=${OPTARG:-}" )
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
	"shared:s3:setup:prepare")
		if [ "${var_run__general__define_s3_backup_lifecycle:-}" = 'true' ]; then
			cmd="s3:subtask:s3_backup"
			info "$command - $cmd - define the backup bucket lifecycle policy"
			>&2 "$pod_script_env_file" "$cmd" --s3_cmd=lifecycle --task_info="$title"
		fi

		if [ "${var_run__general__define_s3_uploads_lifecycle:-}" = 'true' ]; then
			cmd="s3:subtask:s3_uploads"
			info "$command - $cmd - define the uploads bucket lifecycle policy"
			>&2 "$pod_script_env_file" "$cmd" --s3_cmd=lifecycle --task_info="$title"
		fi
		;;
	"shared:s3:replicate:backup")
		task_name='s3_backup_replica'

		opts=()

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--s3_cmd=sync" )

		opts+=( "--s3_src_alias=backup" )
		opts+=( "--s3_remote_src=true" )
		opts+=( "--s3_bucket_src_name=$var_task__s3_backup__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_src_path=${var_task__s3_backup__s3_subtask__bucket_path:-}" )

		opts+=( "--s3_dest_alias=backup_replica" )
		opts+=( "--s3_remote_dest=true" )
		opts+=( "--s3_bucket_dest_name=$var_task__s3_backup_replica__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_dest_path=${var_task__s3_backup_replica__s3_subtask__bucket_path:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"shared:s3:replicate:uploads")
		task_name='s3_uploads_replica'

		opts=()

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--s3_cmd=sync" )

		opts+=( "--s3_src_alias=uploads" )
		opts+=( "--s3_remote_src=true" )
		opts+=( "--s3_bucket_src_name=$var_task__s3_uploads__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_src_path=${var_task__s3_uploads__s3_subtask__bucket_path:-}" )

		opts+=( "--s3_dest_alias=uploads_replica" )
		opts+=( "--s3_remote_dest=true" )
		opts+=( "--s3_bucket_dest_name=$var_task__s3_uploads_replica__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_dest_path=${var_task__s3_uploads_replica__s3_subtask__bucket_path:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"shared:s3:task:"*)
		task_name="${command#shared:s3:task:}"

		prefix="var_task__${task_name}__s3_subtask_"

		param_cli="${prefix}_cli"
		param_cli_cmd="${prefix}_cli_cmd"
		param_alias="${prefix}_alias"

		alias="${!param_alias:-}"

		if [ -z "${!param_alias:-}" ]; then
			alias="${arg_s3_alias:-}"
		fi

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--s3_alias=$alias" )

		param_names=()
		param_names+=( "service" )
		param_names+=( "tmp_dir" )
		param_names+=( "endpoint" )

		for param_name in "${param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--s3_${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		opts+=( "--s3_opts" )
		opts+=( ${args[@]+"${args[@]}"} )

		inner_cmd="s3:main:${!param_cli}:${!param_cli_cmd}:cmd"
		info "$command - $inner_cmd"
		"$pod_script_env_file" "$inner_cmd" "${opts[@]}"
		;;
	"s3:task:"*)
		task_name="${command#s3:task:}"
		prefix="var_task__${task_name}__s3_task_"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		for param_name in "${task_param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--s3_${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask:"*)
		task_name="${command#s3:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		for param_name in "${task_param_names[@]}"; do
			arg_param_name="arg_s3_$param_name"

			if [ -n "${!arg_param_name:-}" ]; then
				opts+=( "--s3_${param_name}=${!arg_param_name:-}" )
			fi
		done

		opts+=( ${s3_task_args[@]+"${s3_task_args[@]}"} )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask")
		prefix="var_task__${arg_task_name}__s3_subtask_"

		param_cli="${prefix}_cli"
		param_cli_cmd="${prefix}_cli_cmd"
		param_alias="${prefix}_alias"
		param_bucket_name="${prefix}_bucket_name"
		param_bucket_path="${prefix}_bucket_path"
		param_bucket_src_name="${prefix}_bucket_src_name"
		param_bucket_src_path="${prefix}_bucket_src_path"
		param_bucket_dest_name="${prefix}_bucket_dest_name"
		param_bucket_dest_path="${prefix}_bucket_dest_path"

		s3_cli="${!param_cli}"
		alias="${!param_alias:-}"

		if [ -z "${!param_alias:-}" ]; then
			alias="${arg_s3_alias:-}"
		fi

		s3_src_alias="$alias"
		bucket_src_name="${!param_bucket_name:-}"
		bucket_src_path="${!param_bucket_path:-}"

		if [ -n "${!param_bucket_src_name:-}" ]; then
			s3_src_alias="${!param_src_alias:-}"
			bucket_src_name="${!param_bucket_src_name:-}"
			bucket_src_path="${!param_bucket_src_path:-}"
		fi

		if [ -n "${arg_s3_bucket_src_name:-}" ]; then
			s3_src_alias="${arg_s3_src_alias:-}"
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

		s3_dest_alias="$alias"
		bucket_dest_name="${!param_bucket_name:-}"
		bucket_dest_path="${!param_bucket_path:-}"

		if [ -n "${!param_bucket_dest_name:-}" ]; then
			s3_dest_alias="${!param_dest_alias:-}"
			bucket_dest_name="${!param_bucket_dest_name:-}"
			bucket_dest_path="${!param_bucket_dest_path:-}"
		fi

		if [ -n "${arg_s3_bucket_dest_name:-}" ]; then
			s3_dest_alias="${arg_s3_dest_alias:-}"
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

		opts=( "--task_info=$title" )
		opts+=( "--s3_alias=$alias" )

		for param_name in "${subtask_param_names[@]}"; do
			arg_var_param_name="${prefix}_${param_name}"

			if [ -n "${!arg_var_param_name:-}" ]; then
				opts+=( "--s3_${param_name}=${!arg_var_param_name:-}" )
			fi
		done

		[ -n "$s3_src_alias" ] && opts+=( "--s3_src_alias=$s3_src_alias" )
		[ -n "$s3_src" ] && opts+=( "--s3_src=$s3_src" )
		[ -n "$s3_dest_alias" ] && opts+=( "--s3_dest_alias=$s3_dest_alias" )
		[ -n "$s3_dest" ] && opts+=( "--s3_dest=$s3_dest" )

		for param_name in "${subtask_args_param_names[@]}"; do
			arg_param_name="arg_s3_$param_name"

			if [ -n "${!arg_param_name:-}" ]; then
				opts+=( "--s3_${param_name}=${!arg_param_name:-}" )
			fi
		done

		opts+=( ${s3_subtask_args[@]+"${s3_subtask_args[@]}"} )

		inner_cmd="s3:main:$s3_cli:${!param_cli_cmd}:$arg_s3_cmd"
		info "$command - $inner_cmd"
		"$pod_script_env_file" "$inner_cmd" "${opts[@]}"
		;;
	"s3:main:awscli:"*)
		"$pod_script_awscli_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"s3:main:mc:"*)
		"$pod_script_mc_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"s3:main:rclone:"*)
		"$pod_script_rclone_file" "$command" ${args[@]+"${args[@]}"}
		;;
	*)
		error "$title: Invalid command"
		;;
esac
