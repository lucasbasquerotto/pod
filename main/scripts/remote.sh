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
		task_short_name ) task_short_name="${OPTARG:-}";;
		task_kind ) task_kind="${OPTARG:-}";;
		toolbox_service ) toolbox_service="${OPTARG:-}";;
		s3_task_name ) s3_task_name="${OPTARG:-}";;
		s3_bucket_name ) s3_bucket_name="${OPTARG:-}" ;;
		s3_bucket_path ) s3_bucket_path="${OPTARG:-}";;

		backup_src_base_dir ) backup_src_base_dir="${OPTARG:-}";;
		backup_src_dir ) backup_src_dir="${OPTARG:-}";;
		backup_src_file ) backup_src_file="${OPTARG:-}";;
		backup_tmp_base_dir ) backup_tmp_base_dir="${OPTARG:-}";;
		backup_bucket_sync_dir ) backup_bucket_sync_dir="${OPTARG:-}";;

		restore_dest_dir ) restore_dest_dir="${OPTARG:-}";;
		restore_tmp_dir ) restore_tmp_dir="${OPTARG:-}";;
		restore_local_zip_file ) restore_local_zip_file="${OPTARG:-}" ;;
		restore_remote_zip_file ) restore_remote_zip_file="${OPTARG:-}" ;;
		restore_remote_bucket_path_dir ) restore_remote_bucket_path_dir="${OPTARG:-}" ;;
		restore_remote_bucket_path_file ) restore_remote_bucket_path_file="${OPTARG:-}";;
		restore_zip_inner_dir ) restore_zip_inner_dir="${OPTARG:-}";;
		restore_dest_file ) restore_dest_file="${OPTARG:-}";;

		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"backup")
		info "$command - started"

		info "$command - start needed services"
		>&2 "$pod_script_env_file" up "$toolbox_service"

		tmp_dir_name="backup-$task_short_name-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		tmp_dir="$backup_tmp_base_dir/$tmp_dir_name"
		bucket_prefix="$s3_bucket_name/$s3_bucket_path"
		bucket_prefix="$(echo "$bucket_prefix" | tr -s /)"
		backup_bucket_sync_dir_full="$s3_bucket_name/$s3_bucket_path/${backup_bucket_sync_dir:-}"
		backup_bucket_sync_dir_full="$(echo "$backup_bucket_sync_dir_full" | tr -s /)"

		info "$command - clean tmp directory ($tmp_dir) and create main directory ($tmp_dir)"
		>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail
			rm -rf "/$tmp_dir"
			mkdir -p "/$tmp_dir"
			mkdir -p "/$tmp_dir"
		SHELL

		if [ -z "${backup_bucket_sync_dir:-}" ]; then
			if [ "$task_kind" = "dir" ]; then
				dest_file="$task_short_name.zip"
				src_full_path="/$backup_src_base_dir/$backup_src_dir"
				dest_full_path="/$tmp_dir/$dest_file"
				msg="$src_full_path to $dest_full_path (inside toolbox)"

				info "$command - zip backup directory - $msg"
				>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
					set -eou pipefail
					cd "/$src_full_path"
					zip -r "$dest_full_path" .
				SHELL
			elif [ "$task_kind" = "file" ]; then
				dest_file="$task_short_name.zip"
				src_full_path="/$backup_src_base_dir/$backup_src_file"
				dest_full_path="/$tmp_dir/$dest_file"
				msg="$src_full_path to $dest_full_path (inside toolbox)"

				if [ "$src_full_path" != "$dest_full_path" ]; then
					if [ "${backup_src_file##*.}" = "zip" ]; then
						info "$command - move backup file - $msg"
						>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
							set -eou pipefail
							mv "/$backup_src_base_dir/$backup_src_file" "/$tmp_dir/$dest_file"
						SHELL
					else
						info "$command - zip backup file - $msg"
						>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
							set -eou pipefail
							zip -j "/$tmp_dir/$dest_file" "/$backup_src_base_dir/$backup_src_file"
						SHELL
					fi
				fi
			else
				error "$command: $task_kind: task_kind invalid value"
			fi
		fi

		if [ ! -z "${s3_bucket_name:-}" ]; then
			empty_bucket="$("$pod_script_env_file" "$s3_task_name" --s3_cmd=is_empty_bucket)"

			if [ "$empty_bucket" = "true" ]; then
				info "$command - $toolbox_service - $s3_task_name - create bucket $s3_bucket_name"
				>&2 "$pod_script_env_file" "$s3_task_name" --s3_cmd=create-bucket
			fi

			if [ -z "${backup_bucket_sync_dir:-}" ]; then
				src="/$tmp_dir/"
				dest="s3://$bucket_prefix/$tmp_dir_name/"

				msg="sync local tmp directory with bucket - $src to $dest"
				>&2 "$pod_script_env_file" "$s3_task_name" --s3_cmd=sync \
					"--s3_src=$src" "--s3_dest=$dest"
			else
				if [ "$task_kind" = "dir" ]; then
					src="/$backup_src_base_dir/$backup_src_dir/"
				elif [ "$task_kind" = "file" ]; then
					src="/$backup_src_base_dir/"
					s3_opts=( --exclude "*" --include "$backup_src_file" )
				else
					error "$command: $task_kind: task_kind invalid value"
				fi

				dest="s3://$backup_bucket_sync_dir_full/"

				msg="sync local src directory with bucket - $src to $dest"
				info "$command - $toolbox_service - $s3_task_name - $msg"
				>&2 "$pod_script_env_file" "$s3_task_name" --s3_cmd=sync \
					"--s3_src=$src" "--s3_dest=$dest" --s3_opts="${s3_opts:-}"
			fi
		fi

		info "$command - generated backup file(s) at '/$tmp_dir'"
		;;  
	"restore")
		bucket_prefix="$s3_bucket_name/$s3_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		
		zip_file=""
		restore_remote_src=""
		restore_local_dest=""

		info "$command - $toolbox_service - restore"
		>&2 "$pod_script_env_file" up "$toolbox_service"
		>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail
			rm -rf "/$restore_tmp_dir"
			mkdir -p "/$restore_tmp_dir"
		SHELL

		if [ ! -z "${restore_local_zip_file:-}" ]; then
			info "$command - restore from local dir"
			zip_file="$restore_local_zip_file"
		elif [ ! -z "${restore_remote_zip_file:-}" ]; then
			info "$command - restore from remote dir"

			zip_file_name="$task_short_name-$key.zip"
			zip_file="/$restore_tmp_dir/$zip_file_name"

			>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" \
				curl -L -o "$zip_file" -k "$restore_remote_zip_file"
		elif [ ! -z "${restore_remote_bucket_path_dir:-}" ]; then
			s3_bucket_path="$bucket_prefix/$restore_remote_bucket_path_dir"
			s3_bucket_path=$(echo "$s3_bucket_path" | tr -s /)
			
			restore_remote_src="s3://$s3_bucket_path"
		elif [ ! -z "${restore_remote_bucket_path_file:-}" ]; then
			msg="$command - restore zip file from remote bucket"
			info "$msg [$restore_remote_src -> $restore_local_dest]"
		
			zip_file_name="$task_short_name-$key.zip"
			zip_file="$restore_tmp_dir/$zip_file_name"

			s3_bucket_path="$bucket_prefix/$restore_remote_bucket_path_file"
			s3_bucket_path=$(echo "$s3_bucket_path" | tr -s /)
			
			restore_remote_src="s3://$s3_bucket_path"
			restore_local_dest="/$zip_file"
			restore_local_dest=$(echo "$restore_local_dest" | tr -s /)

			info "$command - $toolbox_service - $s3_task_name - copy bucket file to local path"
			>&2 "$pod_script_env_file" "$s3_task_name" --s3_cmd=cp \
				"--s3_src=$restore_remote_src" "--s3_dest=$restore_local_dest"
		else
			error "$command: no source provided"
		fi

		restore_path=''

		if [ ! -z "${restore_remote_bucket_path_dir:-}" ]; then
			msg="$command - restore from remote bucket directly to local directory"
			info "$msg [$restore_remote_src -> /$restore_dest_dir]"
			>&2 "$pod_script_env_file" "$s3_task_name" --s3_cmd=sync \
				"--s3_src=$restore_remote_src" "--s3_dest=/$restore_dest_dir"

			restore_path="/$restore_dest_dir"
		else
			if [ "$task_kind" = "dir" ]; then
				info "$command - unzip to directory $restore_tmp_dir"
				>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" \
					unzip "/$zip_file" -d "/$restore_tmp_dir"

				if [ "$restore_tmp_dir" != "$restore_dest_dir" ]; then
					info "$command - restore - main"
					
					>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
						set -eou pipefail
						cp -r "/$restore_tmp_dir/${restore_zip_inner_dir:-}"/. "/$restore_dest_dir/"
						rm -rf "/$restore_tmp_dir"
					SHELL						
				fi
				
				restore_path="/$restore_dest_dir"
			elif [ "$task_kind" = "file" ]; then
				info "$command - unzip to directory $restore_dest_dir"
				>&2 "$pod_script_env_file" exec-nontty "$toolbox_service" \
					unzip "/$zip_file" -d "/$restore_dest_dir"

				restore_path="/$restore_dest_dir/${restore_dest_file:-}"
			else
				error "$command: $task_kind: invalid value for task_kind"
			fi
		fi

		echo "$restore_path"
		;;
	*)
		error "$command: invalid command"
		;;
esac
