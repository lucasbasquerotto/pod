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
		task_kind ) arg_task_kind="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		task_name_s3 ) arg_task_name_s3="${OPTARG:-}";;

		backup_src_base_dir ) arg_backup_src_base_dir="${OPTARG:-}";;
		backup_src_dir ) arg_backup_src_dir="${OPTARG:-}";;
		backup_src_file ) arg_backup_src_file="${OPTARG:-}";;
		backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		backup_zip_file ) arg_backup_zip_file="${OPTARG:-}";;
		backup_bucket_static_dir ) arg_backup_bucket_static_dir="${OPTARG:-}";;
		backup_bucket_sync_dir ) arg_backup_bucket_sync_dir="${OPTARG:-}";;

		restore_dest_base_dir ) arg_restore_dest_base_dir="${OPTARG:-}";;
		restore_dest_file ) arg_restore_dest_file="${OPTARG:-}";;
		restore_tmp_dir ) arg_restore_tmp_dir="${OPTARG:-}";;
		restore_local_file ) arg_restore_local_file="${OPTARG:-}" ;;
		restore_remote_file ) arg_restore_remote_file="${OPTARG:-}" ;;
		restore_remote_bucket_path_file ) arg_restore_remote_bucket_path_file="${OPTARG:-}";;
		restore_remote_bucket_path_dir ) arg_restore_remote_bucket_path_dir="${OPTARG:-}" ;;
		restore_is_zip_file ) arg_restore_is_zip_file="${OPTARG:-}";;
		restore_zip_tmp_file_name ) arg_restore_zip_tmp_file_name="${OPTARG:-}";;
		restore_zip_pass ) arg_restore_zip_pass="${OPTARG:-}";;
		restore_zip_inner_dir ) arg_restore_zip_inner_dir="${OPTARG:-}";;
		restore_zip_inner_file ) arg_restore_zip_inner_file="${OPTARG:-}";;

		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"backup")
		info "$command - started"

		info "$command - start needed services"
		>&2 "$pod_script_env_file" up "$arg_toolbox_service"

		if [ -z "${arg_backup_bucket_sync_dir:-}" ]; then			
			info "$command - create the backup directory ($arg_backup_local_dir)"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" mkdir -p "$arg_backup_local_dir"

			extension=${arg_backup_zip_file##*.}

			if [ "$extension" != "zip" ]; then
				msg="found: $extension ($arg_backup_zip_file)"
				error "$command: backup local file extension should be zip - $msg"
			fi

			dest_full_path="$arg_backup_local_dir/$arg_backup_zip_file"

			if [ "$arg_task_kind" = "dir" ]; then
				msg="zipping $arg_backup_src_base_dir/${arg_backup_src_dir:-} to $dest_full_path (inside toolbox)"
				info "$command - zip backup directory - $msg"
				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
					set -eou pipefail
					cd "$arg_backup_src_base_dir"
					zip -r "$dest_full_path" ./"${arg_backup_src_dir:-}"
				SHELL
			elif [ "$arg_task_kind" = "file" ]; then
				src_full_path="$arg_backup_src_base_dir/$arg_backup_src_file"
				msg="$src_full_path to $dest_full_path (inside toolbox)"

				if [ "$src_full_path" != "$dest_full_path" ]; then
					if [ "${arg_backup_src_file##*.}" = "zip" ]; then
						info "$command - move backup file - $msg"
						>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
							mv "$arg_backup_src_base_dir/$arg_backup_src_file" "$dest_full_path"
					else
						info "$command - zip backup file - $msg"
						>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
							zip -j "$dest_full_path" "$arg_backup_src_base_dir/$arg_backup_src_file"
					fi
				fi
			else
				error "$command: $arg_task_kind: arg_task_kind invalid value"
			fi
		else
			if [ -n "${arg_backup_zip_file:-}" ]; then
				msg="backup_zip_file (${arg_backup_zip_file:-}) shouldn't be defined when"
				msg="$msg backup_bucket_sync_dir (${arg_backup_bucket_sync_dir:-}) is defined"
				error "$command: $msg"
			fi
		fi

		if [ -n "${arg_task_name_s3:-}" ]; then
			empty_bucket="$("$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=is_empty_bucket)"

			if [ "$empty_bucket" = "true" ]; then
				info "$command - $arg_toolbox_service - $arg_task_name_s3 - create bucket"
				>&2 "$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=create-bucket
			fi

			if [ -z "${arg_backup_bucket_sync_dir:-}" ]; then
				src="$arg_backup_local_dir/"
				s3_dest_dir="${arg_backup_bucket_static_dir:-$(basename "$arg_backup_local_dir")}"

				msg="sync local backup directory with bucket - $src to $s3_dest_dir (s3)"
				>&2 "$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=sync \
					--s3_src="$src" \
					--s3_dest_rel="$s3_dest_dir" \
					--s3_file="$arg_backup_zip_file"
			else
				s3_file=''

				if [ "$arg_task_kind" = "dir" ]; then
					src="$arg_backup_src_base_dir/$arg_backup_src_dir/"
				elif [ "$arg_task_kind" = "file" ]; then
					src="$arg_backup_src_base_dir/"
					s3_file="$arg_backup_src_file"
				else
					error "$command: $arg_task_kind: arg_task_kind invalid value"
				fi

				msg="sync local src directory with bucket - $src to $arg_backup_bucket_sync_dir (s3)"
				info "$command - $arg_toolbox_service - $arg_task_name_s3 - $msg"
				>&2 "$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=sync \
					--s3_src="$src" \
					--s3_dest_rel="$arg_backup_bucket_sync_dir" \
					--s3_file="$s3_file"
			fi
		fi
		;;  
	"restore")
		restore_path=''
		arg_restore_dest_base_dir_full="$arg_restore_dest_base_dir"

		if [ -n "${arg_restore_remote_bucket_path_dir:-}" ]; then
			info "$command - create the restore destination directory ($arg_restore_dest_base_dir_full)"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				mkdir -p "$arg_restore_dest_base_dir_full"

			s3_file=''

			if [ -n "${arg_restore_dest_file:-}" ]; then
				s3_file="$arg_restore_dest_file"
				restore_path="$arg_restore_dest_base_dir_full/$arg_restore_dest_file"
			else
				restore_path="$arg_restore_dest_base_dir_full"
			fi
			
			msg="$arg_restore_remote_bucket_path_dir (s3) to $arg_restore_dest_base_dir_full"
			info "$command - restore from remote bucket directly to local directory - $msg"
			>&2 "$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=sync \
				--s3_src_rel="$arg_restore_remote_bucket_path_dir" \
				--s3_dest="$arg_restore_dest_base_dir_full" \
				--s3_file="$s3_file"
		else
			restore_file=""
			restore_local_dest=""

			info "$command - $arg_toolbox_service - restore"
			>&2 "$pod_script_env_file" up "$arg_toolbox_service"
			
			msg="create the restore temporary directory ($arg_restore_tmp_dir)"
			msg="$msg and the destination directory ($arg_restore_dest_base_dir_full)"
			info "$command - $msg"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail
				mkdir -p "$arg_restore_tmp_dir"
				mkdir -p "$arg_restore_dest_base_dir_full"
			SHELL
			
			if [ "${arg_restore_is_zip_file:-}" != "true" ]; then
				if [ "$arg_task_kind" = "dir" ]; then
					msg="trying to restore a directory using a non-zipped file"
					msg="$msg (instead, use a zip file or specify a bucket directory as the source)"
					error "$command - $msg"	
				fi

				restore_file_default="$arg_restore_dest_file"
			else
				extension=${arg_restore_zip_tmp_file_name##*.}

				if [ "$extension" != "zip" ]; then
					msg="found: $extension ($arg_restore_zip_tmp_file_name)"
					error "$command: zip tmp file extension should be zip - $msg"
				fi

				restore_file_default="$arg_restore_tmp_dir/$arg_restore_zip_tmp_file_name"
			fi

			if [ -n "${arg_restore_local_file:-}" ]; then
				info "$command - restore from local file"
				restore_file="$arg_restore_local_file"
			elif [ -n "${arg_restore_remote_file:-}" ]; then
				info "$command - restore from remote file"
				restore_file="$restore_file_default"

				>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					curl -L -o "$restore_file" -k "$arg_restore_remote_file"
			elif [ -n "${arg_restore_remote_bucket_path_file:-}" ]; then
				msg="$command - $arg_toolbox_service - $arg_task_name_s3"
				msg="$msg - restore a file from remote bucket"
				info "$msg [$arg_restore_remote_bucket_path_file (s3) -> $restore_local_dest]"

				restore_file="$restore_file_default"

				>&2 "$pod_script_env_file" "$arg_task_name_s3" --s3_cmd=cp \
					--s3_src_rel="$arg_restore_remote_bucket_path_file" \
					--s3_dest="$restore_file"
			else
				error "$command: no source provided"
			fi
			
			info "$command - restore - main ($arg_task_kind) - $restore_file to $arg_restore_tmp_dir"
			unzip_opts=()

			if [ -n "${arg_restore_zip_pass:-}" ]; then
				unzip_opts=( -P "$arg_restore_zip_pass" )
			fi

			if [ "$arg_task_kind" = "dir" ]; then
				if [ "${arg_restore_is_zip_file:-}" = "true" ]; then
					restore_tmp_dir_full="$arg_restore_tmp_dir"

					if [ -n "${arg_restore_zip_inner_dir:-}" ]; then
						restore_tmp_dir_full="$arg_restore_tmp_dir/${arg_restore_zip_inner_dir:-}"
					fi

					info "$command - unzip $restore_file to directory $restore_tmp_dir_full"
					>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
						set -eou pipefail

						rm -rf "$restore_tmp_dir_full"

						unzip ${unzip_opts[@]+"${unzip_opts[@]}"} "$restore_file" -d "$arg_restore_tmp_dir"
				
						if [ "$restore_tmp_dir_full" != "$arg_restore_dest_base_dir_full" ]; then
							cp -r "$restore_tmp_dir_full"/. "$arg_restore_dest_base_dir_full/"
							rm -rf "$restore_tmp_dir_full"
						fi
					SHELL
				else
					msg="trying to restore a directory using a non-zipped file"
					msg="$msg (use a zip file instead, or specify a bucket directory as the source)"
					error "$command - $msg"	
				fi
				
				restore_path="$arg_restore_dest_base_dir_full"
			elif [ "$arg_task_kind" = "file" ]; then
				if [ "${arg_restore_is_zip_file:-}" = "true" ]; then
					info "$command - unzip $restore_file to directory $arg_restore_tmp_dir"
					intermediate="$arg_restore_tmp_dir/$arg_restore_zip_inner_file"
					dest="$arg_restore_dest_base_dir_full/$arg_restore_dest_file"

					if [ "$restore_file" != "$dest" ]; then
						>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
							set -eou pipefail

							unzip ${unzip_opts[@]+"${unzip_opts[@]}"} "$restore_file" -d "$arg_restore_tmp_dir"

							if [ "$intermediate" != "$dest" ]; then
								mv "$intermediate" "$dest"
								rm -rf "$arg_restore_tmp_dir"
							fi
						SHELL
					fi
				else
					info "$command - move $restore_file to directory $arg_restore_dest_base_dir_full"
					>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
						mv "$restore_file" "$arg_restore_dest_base_dir_full/"
				fi

				restore_path="$arg_restore_dest_base_dir_full/$arg_restore_dest_file"
			else
				error "$command: $arg_task_kind: invalid value for arg_task_kind"
			fi
		fi

		info "$command - restored at: $restore_path"
		;;
	*)
		error "$command: invalid command"
		;;
esac
