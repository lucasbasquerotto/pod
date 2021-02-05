#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2153
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		subtask_cmd_s3 ) arg_subtask_cmd_s3="${OPTARG:-}";;

		backup_src_dir ) arg_backup_src_dir="${OPTARG:-}";;
		backup_src_file ) arg_backup_src_file="${OPTARG:-}";;
		backup_bucket_sync_dir ) arg_backup_bucket_sync_dir="${OPTARG:-}";;
		backup_ignore_path ) arg_backup_ignore_path="${OPTARG:-}";;
		backup_date_format ) arg_backup_date_format="${OPTARG:-}";;
		backup_time_format ) arg_backup_time_format="${OPTARG:-}";;
		backup_datetime_format ) arg_backup_datetime_format="${OPTARG:-}";;

		restore_use_s3 ) arg_restore_use_s3="${OPTARG:-}";;
		restore_s3_sync ) arg_restore_s3_sync="${OPTARG:-}";;
		restore_dest_dir ) arg_restore_dest_dir="${OPTARG:-}";;
		restore_dest_file ) arg_restore_dest_file="${OPTARG:-}";;
		restore_remote_file ) arg_restore_remote_file="${OPTARG:-}" ;;
		restore_bucket_path_dir ) arg_restore_bucket_path_dir="${OPTARG:-}";;
		restore_bucket_path_file ) arg_restore_bucket_path_file="${OPTARG:-}";;

		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"backup")
		info "$title - started"

		info "$title - start needed services"
		>&2 "$pod_script_env_file" up "$arg_toolbox_service"

		if [ -z "${arg_subtask_cmd_s3:-}" ]; then
			error "$title: only s3 is supported for remote backup"
		fi

		if [ -z "${arg_backup_src_dir:-}" ] && [ -z "${arg_backup_src_file:-}" ]; then
			error "$title: backup_src_dir and backup_src_file parameters are both empty"
		elif [ -n "${arg_backup_src_dir:-}" ] && [ -n "${arg_backup_src_file:-}" ]; then
			error "$title: backup_src_dir and backup_src_file parameters are both specified"
		fi

		backup_src="${arg_backup_src_file:-$arg_backup_src_dir}"

		src_type="$("$pod_script_env_file" "run:util:file:type" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$command" \
			--toolbox_service="$arg_toolbox_service" \
			--path="$backup_src" \
			|| error "$title: file:type (dest_file)"
		)"

		if [ -z "$src_type" ]; then
			error "$title: backup source ($backup_src) not found"
		fi

		backup_bucket_sync_dir="${arg_backup_bucket_sync_dir:-}"

		if [ -n "${arg_backup_bucket_sync_dir:-}" ]; then
			backup_bucket_sync_dir="$("$pod_script_env_file" "run:util:replace_placeholders" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$command" \
				--toolbox_service="$arg_toolbox_service" \
				--value="${arg_backup_bucket_sync_dir:-}" \
				--date_format="${arg_backup_date_format:-}" \
				--time_format="${arg_backup_time_format:-}" \
				--datetime_format="${arg_backup_datetime_format:-}")" \
				|| error "$command: replace_placeholders (backup_bucket_sync_dir)"
		fi

		if [ -n "${arg_backup_src_file:-}" ]; then
			if [ "$src_type" != 'file' ]; then
				msg="backup source (${arg_backup_src_file:-}) is not a file ($src_type)"
				error "$title: $msg"
			fi

			backup_src_dir="$(dirname "$arg_backup_src_file")"
			backup_bucket_file="$(basename "$arg_backup_src_file")"

			msg="sync local backup file with bucket"
			bucket_path="${backup_bucket_sync_dir:-}/${backup_bucket_file}"
			info "$title - $msg - $arg_backup_src_file to $bucket_path (s3)"
		else
			if [ "$src_type" != 'dir' ]; then
				msg="backup source (${arg_backup_src_dir:-}) is not a directory ($src_type)"
				error "$title: $msg"
			fi

			backup_src_dir="$arg_backup_src_dir"
			backup_bucket_file=""
			msg="sync local backup directory with bucket"
			info "$title - $msg - $arg_backup_src_dir to /${backup_bucket_sync_dir:-} (s3)"
		fi

		empty_bucket="$("$pod_script_env_file" "$arg_subtask_cmd_s3" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$arg_subtask_cmd" \
			--s3_cmd=is_empty_bucket)"

		if [ "$empty_bucket" = "true" ]; then
			info "$title - $arg_toolbox_service - $arg_subtask_cmd_s3 - create bucket"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=create_bucket \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd"
		fi

		>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=sync \
			--s3_src="$backup_src_dir" \
			--s3_dest_rel="$backup_bucket_sync_dir" \
			--s3_remote_dest="true" \
			--s3_file="$backup_bucket_file" \
			--s3_ignore_path="${arg_backup_ignore_path:-}" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$arg_subtask_cmd"
		;;
	"restore")
		info "$title - restore"
		>&2 "$pod_script_env_file" up "$arg_toolbox_service"

		if [ "$arg_restore_use_s3" = "true" ] && [ "$arg_restore_s3_sync" = "true" ]; then
			if [ -z "${arg_restore_dest_dir:-}" ] && [ -z "${arg_restore_dest_file:-}" ]; then
				error "$title: restore_dest_dir and restore_dest_file parameters are both empty"
			elif [ -n "${arg_restore_dest_dir:-}" ] && [ -n "${arg_restore_dest_file:-}" ]; then
				error "$title: restore_dest_dir and restore_dest_file parameters are both specified"
			fi

			if [ -n "${arg_restore_bucket_path_file:-}" ]; then
				error "$title: restore_bucket_path_file parameter is specified with the sync option"
			fi

			if [ -n "${arg_restore_dest_file:-}" ]; then
				restore_dest_dir="$(dirname "$arg_restore_dest_file")"
				restore_bucket_file="$(basename "$arg_restore_dest_file")"

				msg="create the destination directory for the file"
				info "$title - $msg (${arg_restore_dest_file:-})"
				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					mkdir -p "$restore_dest_dir"
			else
				restore_dest_dir="$arg_restore_dest_dir"
				restore_bucket_file=""

				msg="create the destination directory"
				info "$title - $msg (${restore_dest_dir:-})"
				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					mkdir -p "$restore_dest_dir"
			fi

			msg="/${arg_restore_bucket_path_dir:-} (s3) to ${restore_dest_dir:-}"
			info "$title - restore from remote bucket directly to local directory - $msg"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=sync \
				--s3_src_rel="${arg_restore_bucket_path_dir:-}" \
				--s3_remote_src="true" \
				--s3_dest="$restore_dest_dir" \
				--s3_file="$restore_bucket_file" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd"
		else
			if [ -z "${arg_restore_dest_file:-}" ]; then
				error "$title: restore_dest_file parameter is empty"
			fi

			msg="create the destination directory for the file"
			info "$title - $msg (${arg_restore_dest_file:-})"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				mkdir -p "$(dirname "$arg_restore_dest_file")"

			if [ -n "${arg_restore_remote_file:-}" ]; then
				msg="${arg_restore_remote_file:-} to ${arg_restore_dest_file:-}"
				info "$title - restore from remote file ($msg)"
				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					curl -L -o "$arg_restore_dest_file" -k "$arg_restore_remote_file"
			elif [ "$arg_restore_use_s3" = "true" ] && [ "$arg_restore_s3_sync" != "true" ]; then
				if [ -z "${arg_restore_bucket_path_file:-}" ]; then
					error "$title: restore_bucket_path_file parameter is empty"
				elif [ -n "${arg_restore_bucket_path_dir:-}" ]; then
					error "$title: restore_bucket_path_dir parameter is specified without the sync option"
				fi

				msg="${arg_restore_bucket_path_file:-} (s3) -> ${arg_restore_dest_file:-}"
				info "$title - ${arg_subtask_cmd_s3:-} - restore a file from a remote bucket [$msg]"
				>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=cp \
					--s3_src_rel="$arg_restore_bucket_path_file" \
					--s3_dest="$arg_restore_dest_file" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			else
				error "$title: no source provided"
			fi
		fi
		;;
	*)
		error "$title: invalid command"
		;;
esac
