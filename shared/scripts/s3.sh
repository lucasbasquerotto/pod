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
		s3_older_than_days ) arg_s3_older_than_days="${OPTARG:-}";;
		s3_file ) arg_s3_file="${OPTARG:-}";;
		s3_path ) arg_s3_path="${OPTARG:-}";;
		s3_test ) arg_s3_test="${OPTARG:-}";;
		s3_ignore_path ) arg_s3_ignore_path="${OPTARG:-}";;
		??* ) ;; ## ignore
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
		param_service="${prefix}_service"
		param_tmp_dir="${prefix}_tmp_dir"
		param_alias="${prefix}_alias"
		param_endpoint="${prefix}_endpoint"

		alias="${!param_alias:-}"

		if [ -z "${!param_alias:-}" ]; then
			alias="${arg_s3_alias:-}"
		fi

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--s3_service=${!param_service:-}" )
		opts+=( "--s3_tmp_dir=${!param_tmp_dir:-}" )
		opts+=( "--s3_alias=$alias" )
		opts+=( "--s3_endpoint=${!param_endpoint:-}" )

		opts+=( "--s3_opts" )
		opts+=( ${args[@]+"${args[@]}"} )

		inner_cmd="s3:main:${!param_cli}:${!param_cli_cmd}:cmd"
		info "$command - $inner_cmd"
		"$pod_script_env_file" "$inner_cmd" "${opts[@]}"
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
		opts+=( "--s3_path=${arg_s3_path:-}" )
		opts+=( "--s3_file=${arg_s3_file:-}" )
		opts+=( "--s3_ignore_path=${arg_s3_ignore_path:-}" )
		opts+=( "--s3_older_than_days=${arg_s3_older_than_days:-}" )
		opts+=( "--s3_test=${arg_s3_test:-}" )

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
		param_lifecycle_dir="${prefix}_lifecycle_dir"
		param_lifecycle_file="${prefix}_lifecycle_file"
		param_acl="${prefix}_acl"

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

		opts+=( "--s3_service=${!param_service:-}" )
		opts+=( "--s3_tmp_dir=${!param_tmp_dir:-}" )
		opts+=( "--s3_alias=$alias" )
		opts+=( "--s3_endpoint=${!param_endpoint:-}" )
		opts+=( "--s3_bucket_name=${!param_bucket_name:-}" )
		opts+=( "--s3_lifecycle_dir=${!param_lifecycle_dir:-}" )
		opts+=( "--s3_lifecycle_file=${!param_lifecycle_file:-}" )
		opts+=( "--s3_acl=${!param_acl:-}" )

		opts+=( "--s3_remote_src=${arg_s3_remote_src:-}" )
		opts+=( "--s3_src_alias=$s3_src_alias" )
		opts+=( "--s3_src=${s3_src:-}" )
		opts+=( "--s3_remote_dest=${arg_s3_remote_dest:-}" )
		opts+=( "--s3_dest_alias=$s3_dest_alias" )
		opts+=( "--s3_dest=${s3_dest:-}" )
		opts+=( "--s3_path=${arg_s3_path:-}" )
		opts+=( "--s3_file=${arg_s3_file:-}" )
		opts+=( "--s3_ignore_path=${arg_s3_ignore_path:-}" )
		opts+=( "--s3_older_than_days=${arg_s3_older_than_days:-}" )
		opts+=( "--s3_test=${arg_s3_test:-}" )

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
