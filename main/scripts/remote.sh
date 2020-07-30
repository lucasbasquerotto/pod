#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_script_env_file="$POD_SCRIPT_ENV_FILE"

GRAY="\033[0;90m"
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	msg="$(date '+%F %T') - ${1:-}"
	>&2 echo -e "${GRAY}${msg}${NC}"
}

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
		task_kind ) arg_task_kind="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		subtask_cmd_s3 ) arg_subtask_cmd_s3="${OPTARG:-}";;

		backup_src_base_dir ) arg_backup_src_base_dir="${OPTARG:-}";;
		backup_src_dir ) arg_backup_src_dir="${OPTARG:-}";;
		backup_src_file ) arg_backup_src_file="${OPTARG:-}";;
		backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		backup_file ) arg_backup_file="${OPTARG:-}";;
		backup_bucket_static_dir ) arg_backup_bucket_static_dir="${OPTARG:-}";;
		backup_bucket_sync ) arg_backup_bucket_sync="${OPTARG:-}";;
		backup_bucket_sync_dir ) arg_backup_bucket_sync_dir="${OPTARG:-}";;

		restore_use_s3 ) arg_restore_use_s3="${OPTARG:-}";;
		restore_s3_sync ) arg_restore_s3_sync="${OPTARG:-}";;
		restore_dest_base_dir ) arg_restore_dest_base_dir="${OPTARG:-}";;
		restore_dest_file ) arg_restore_dest_file="${OPTARG:-}";;
		restore_dest_dir ) arg_restore_dest_dir="${OPTARG:-}";;
		restore_remote_file ) arg_restore_remote_file="${OPTARG:-}" ;;
		restore_remote_bucket_path_file ) arg_restore_remote_bucket_path_file="${OPTARG:-}";;
		restore_remote_bucket_path_dir ) arg_restore_remote_bucket_path_dir="${OPTARG:-}" ;;
		restore_recursive_mode ) arg_restore_recursive_mode="${OPTARG:-}";;
		restore_recursive_mode_dir ) arg_restore_recursive_mode_dir="${OPTARG:-}";;
		restore_recursive_mode_file ) arg_restore_recursive_mode_file="${OPTARG:-}";;

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

		empty_bucket="$("$pod_script_env_file" "$arg_subtask_cmd_s3" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$arg_subtask_cmd" \
			--s3_cmd=is_empty_bucket)"

		if [ "$empty_bucket" = "true" ]; then
			info "$title - $arg_toolbox_service - $arg_subtask_cmd_s3 - create bucket"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=create-bucket \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd" \

		fi

		if [ "${arg_backup_bucket_sync:-}" != "true" ]; then
			src="$arg_backup_local_dir/"
			s3_dest_dir="${arg_backup_bucket_static_dir:-$(basename "$arg_backup_local_dir")}"

			msg="sync local backup directory with bucket - $src to $s3_dest_dir (s3)"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=sync \
				--s3_src="$src" \
				--s3_dest_rel="$s3_dest_dir" \
				--s3_remote_dest="true" \
				--s3_file="$arg_backup_file" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd" \

		else
			s3_file=''

			if [ "$arg_task_kind" = "dir" ]; then
				src="$arg_backup_src_base_dir/$arg_backup_src_dir/"
			elif [ "$arg_task_kind" = "file" ]; then
				src="$arg_backup_src_base_dir/"
				s3_file="$arg_backup_src_file"
			else
				error "$title: $arg_task_kind: arg_task_kind invalid value"
			fi

			msg="sync local src directory with bucket - $src to ${arg_backup_bucket_sync_dir:-bucket} (s3)"
			info "$title - $arg_toolbox_service - $arg_subtask_cmd_s3 - $msg"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=sync \
				--s3_src="$src" \
				--s3_dest_rel="${arg_backup_bucket_sync_dir:-}" \
				--s3_remote_dest="true" \
				--s3_file="$s3_file" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd" \

		fi
		;;
	"restore")
		restore_path=''
		restore_dest_base_dir_full="$arg_restore_dest_base_dir"

		if [ -n "${arg_restore_dest_dir:-}" ]; then
			restore_dest_base_dir_full="$arg_restore_dest_base_dir/$arg_restore_dest_dir"
		fi

		if [ "$arg_restore_use_s3" = "true" ] && [ "$arg_restore_s3_sync" = "true" ]; then
			info "$title - create the restore destination directory ($arg_restore_dest_base_dir)"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				mkdir -p "$arg_restore_dest_base_dir"

			s3_file=''

			if [ -n "${arg_restore_dest_file:-}" ]; then
				s3_file="$arg_restore_dest_file"
				restore_path="$arg_restore_dest_base_dir/$arg_restore_dest_file"
			else
				restore_path="$arg_restore_dest_base_dir"
			fi

			msg="/${arg_restore_remote_bucket_path_dir:-} (s3) to $restore_dest_base_dir_full"
			info "$title - restore from remote bucket directly to local directory - $msg"
			>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=sync \
				--s3_src_rel="${arg_restore_remote_bucket_path_dir:-}" \
				--s3_remote_src="true" \
				--s3_dest="$restore_dest_base_dir_full" \
				--s3_file="$s3_file" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd" \

		else
			restore_file=""
			restore_local_dest=""

			info "$title - $arg_toolbox_service - restore"
			>&2 "$pod_script_env_file" up "$arg_toolbox_service"

			info "$title - create the destination directory ($restore_dest_base_dir_full)"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" mkdir -p "$restore_dest_base_dir_full"

			if [ -n "${arg_restore_remote_file:-}" ]; then
				info "$title - restore from remote file"
				restore_file="$restore_file_default"

				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					curl -L -o "$arg_dest_file" -k "$arg_restore_remote_file"
			elif [ "$arg_restore_use_s3" = "true" ] && [ "$arg_restore_s3_sync" != "true" ]; then
				if [ -z "${arg_restore_remote_bucket_path_file:-}" ]; then
					error "$title - restore_remote_bucket_path_file not defined"
				fi
				msg="$title - $arg_toolbox_service - $arg_subtask_cmd_s3"
				msg="$msg - restore a file from remote bucket"
				info "$msg [$arg_restore_remote_bucket_path_file (s3) -> $restore_local_dest]"

				restore_file="$restore_file_default"

				>&2 "$pod_script_env_file" "$arg_subtask_cmd_s3" --s3_cmd=cp \
					--s3_src_rel="$arg_restore_remote_bucket_path_file" \
					--s3_dest="$restore_file" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			else
				error "$title: no source provided"
			fi
		fi

		# >&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
		# 	set -eou pipefail

		# 	if [ -n "${arg_restore_recursive_mode:-}" ]; then
		# 		chmod -R "$arg_restore_recursive_mode" "$restore_dest_base_dir_full"
		# 	fi

		# 	if [ -n "${arg_restore_recursive_mode_dir:-}" ]; then
		# 		find "$restore_dest_base_dir_full" -type d -print0 \
		# 			| xargs -0 chmod "$arg_restore_recursive_mode_dir"
		# 	fi

		# 	if [ -n "${arg_restore_recursive_mode_file:-}" ]; then
		# 		find "$restore_dest_base_dir_full" -type f -print0 \
		# 			| xargs -0 chmod "$arg_restore_recursive_mode_file"
		# 	fi
		# SHELL

		info "$title - restored at: $restore_path"
		;;
	*)
		error "$title: invalid command"
		;;
esac
