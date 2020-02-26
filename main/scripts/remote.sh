#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_script_env_file="$POD_SCRIPT_ENV_FILE"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

args=( "$@" )

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_short_name ) task_short_name="${OPTARG:-}";;
		task_kind ) task_kind="${OPTARG:-}";;
		bucket_name ) bucket_name="${OPTARG:-}" ;;
		bucket_path ) bucket_path="${OPTARG:-}";;
		task_service ) task_service="${OPTARG:-}";;
		tmp_dir ) tmp_dir="${OPTARG:-}" ;;
		s3_endpoint ) s3_endpoint="${OPTARG:-}";;
		use_aws_s3 ) use_aws_s3="${OPTARG:-}";;
		use_s3cmd ) use_s3cmd="${OPTARG:-}";;

		backup_src_dir ) backup_src_dir="${OPTARG:-}";;
		backup_src_file ) backup_src_file="${OPTARG:-}";;
		backup_base_dir ) backup_base_dir="${OPTARG:-}";;
		backup_bucket_sync_dir ) backup_bucket_sync_dir="${OPTARG:-}";;

		restore_dest_dir ) restore_dest_dir="${OPTARG:-}";;
		restore_local_zip_file ) restore_local_zip_file="${OPTARG:-}" ;;
		restore_remote_zip_file ) restore_remote_zip_file="${OPTARG:-}" ;;
		restore_remote_bucket_path_dir ) restore_remote_bucket_path_dir="${OPTARG:-}" ;;
		restore_remote_bucket_path_file ) restore_remote_bucket_path_file="${OPTARG:-}";;
		restore_zip_inner_dir ) restore_zip_inner_dir="${OPTARG:-}";;
		restore_zip_inner_file ) restore_zip_inner_file="${OPTARG:-}";;

		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"backup")
		echo -e "${CYAN}$(date '+%F %T') - $command - started${NC}"

		echo -e "${CYAN}$(date '+%F %T') - $command - start needed services${NC}"
		"$pod_script_env_file" up "$task_service"

		main_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_dir="$backup_base_dir/$main_name"
		bucket_prefix="$bucket_name/$bucket_path"
		bucket_prefix="$(echo "$bucket_prefix" | tr -s /)"
		backup_bucket_sync_dir_full="$bucket_name/$bucket_path/$backup_bucket_sync_dir"
		backup_bucket_sync_dir_full="$(echo "$backup_bucket_sync_dir_full" | tr -s /)"

		echo -e "${CYAN}$(date '+%F %T') - $command - main backup${NC}"
		"$pod_script_env_file" exec-nontty "$task_service" /bin/bash <<-SHELL
			set -eou pipefail

			echo -e "${CYAN}$(date '+%F %T') - $command - create and clean directories${NC}"
			rm -rf "/$tmp_dir"
			mkdir -p "/$tmp_dir"
			mkdir -p "/$main_dir"

			if [ -z "$backup_bucket_sync_dir" ]; then
			  if [ "$task_kind" = "dir" ]; then
					echo -e "${CYAN}$(date '+%F %T') - $command - backup directory ($backup_src_dir)${NC}"
					cp -r "/$backup_src_dir" "/$tmp_dir"
					cd "/$tmp_dir"
					zip -r $task_short_name.zip ./*
					mv "/$tmp_dir/$task_short_name.zip" "/$main_dir/$task_short_name.zip"
				elif [ "$task_kind" = "file" ]; then
					zip -j "/$tmp_dir/$task_short_name.zip" "/$backup_src_dir/$backup_src_file"
					mv "/$tmp_dir/$task_short_name.zip" "/$main_dir/$task_short_name.zip"
				else
					error "[$command] $task_kind: kind invalid value"
				fi
			fi

			if [ ! -z "$bucket_name" ]; then
				if [ "${use_aws_s3:-}" = 'true' ]; then
					error_log_file="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log"

					if ! aws s3 --endpoint="$s3_endpoint" ls "s3://$bucket_name" 2> "\$error_log_file"; then
						if grep -q 'NoSuchBucket' "\$error_log_file"; then
							msg="$command - $task_service - aws_s3 - create bucket $bucket_name"
							echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
							aws s3api create-bucket \
								--endpoint="$s3_endpoint" \
								--bucket "$bucket_name" 
						fi
					fi

					msg="$command - $task_service - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"/$backup_base_dir/" \
						"s3://$bucket_prefix"

					if [ ! -z "$backup_bucket_sync_dir" ]; then
						msg="$command - $task_service - aws_s3 - sync local directory with bucket"
						echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$backup_src_dir/" \
							"s3://$backup_bucket_sync_dir_full/"
					fi
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command - $task_service - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					s3cmd sync "/$backup_base_dir/" "s3://$bucket_prefix"

					if [ ! -z "$backup_bucket_sync_dir" ]; then
						msg="$command - $task_service - s3cmd - sync local directory with bucket"
						echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
						s3cmd sync "/$backup_src_dir/" "s3://$backup_bucket_sync_dir_full/"
					fi
				else
					error "$command - $task_service - not able to sync local backup with bucket"
				fi
			fi
		SHELL

		msg="generated backup file(s) at '/$main_dir'"
		echo -e "${CYAN}$(date '+%F %T') - $command - $msg${NC}"
		;;  
	"restore")		
		bucket_prefix="$bucket_name/$bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		zip_file=""
		restore_remote_src=""
		restore_local_dest=""

		if [ ! -z "${restore_local_zip_file:-}" ]; then
			zip_file="$restore_local_zip_file"
		elif [ ! -z "${restore_remote_zip_file:-}" ]; then
			zip_file_name="$task_short_name-$key.zip"
			zip_file="/$tmp_dir/$zip_file_name"
		elif [ ! -z "${restore_remote_bucket_path_dir:-}" ]; then
			bucket_path="$bucket_prefix/$restore_remote_bucket_path_dir"
			bucket_path=$(echo "$bucket_path" | tr -s /)
			
			restore_remote_src="s3://$bucket_path"
		elif [ ! -z "${restore_remote_bucket_path_file:-}" ]; then
			zip_file_name="$task_short_name-$key.zip"
			zip_file="$tmp_dir/$zip_file_name"

			bucket_path="$bucket_prefix/$restore_remote_bucket_path_file"
			bucket_path=$(echo "$bucket_path" | tr -s /)
			
			restore_remote_src="s3://$bucket_path"
			restore_local_dest="/$zip_file"
			restore_local_dest=$(echo "$restore_local_dest" | tr -s /)
		else
			error "$command: no source provided"
		fi

		>&2 echo -e "${CYAN}$(date '+%F %T') - $command - $task_service - restore${NC}"
		>&2 "$pod_script_env_file" up "$task_service"
		"$pod_script_env_file" exec-nontty "$task_service" /bin/bash <<-SHELL
			set -eou pipefail

			>&2 rm -rf "/$tmp_dir"
			>&2 mkdir -p "/$tmp_dir"
		
			if [ ! -z "${restore_local_zip_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command - restore from local dir${NC}"
			elif [ ! -z "${restore_remote_zip_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command - restore from remote dir${NC}"
				>&2 curl -L -o "$zip_file" -k "$restore_remote_zip_file"
			elif [ ! -z "${restore_remote_bucket_path_file:-}" ]; then
				msg="$command - restore zip file from remote bucket"
				msg="\$msg [$restore_remote_src -> $restore_local_dest]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
			
				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command - $task_service - aws_s3 - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 aws s3 cp \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src" "$restore_local_dest"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command - $task_service - s3cmd - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 s3cmd cp "$restore_remote_src" "$restore_local_dest"
				else
					error "$command - $task_service - not able to copy bucket file to local path"
				fi
			fi

			restore_path=''

			if [ ! -z "${restore_remote_bucket_path_dir:-}" ]; then
				msg="$command - restore from remote bucket directly to local directory"
				msg="\$msg [$restore_remote_src -> /$restore_dest_dir]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
			
				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command - $task_service - aws_s3 - sync bucket dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 aws s3 sync \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src" "/$restore_dest_dir"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command - $task_service - s3cmd - sync bucket dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 s3cmd sync "$restore_remote_src" "/$restore_dest_dir"
				else
					error "$command - $task_service - not able to sync bucket dir to local path"
				fi

				restore_path="/$restore_dest_dir"
			else
				msg="unzip at $tmp_dir"
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command - \$msg${NC}"

				if [ "$task_kind" = "dir" ]; then
					msg="unzip to directory $tmp_dir"
					>&2 echo -e "${CYAN}$(date '+%F %T') - $command - \$msg${NC}"
					>&2 unzip "/$zip_file" -d "/$tmp_dir"

					>&2 echo -e "${CYAN}$(date '+%F %T') - $command - restore - main${NC}"
					>&2 cp -r  "/$tmp_dir/${restore_zip_inner_dir:-}"/. "/$restore_dest_dir/"
					
					restore_path="/$restore_dest_dir"
				elif [ "$task_kind" = "file" ]; then
					msg="unzip to directory $restore_dest_dir"
					>&2 echo -e "${CYAN}$(date '+%F %T') - $command - \$msg${NC}"
					>&2 unzip "/$zip_file" -d "/$restore_dest_dir"

					restore_path="/$restore_dest_dir/${restore_zip_inner_file:-}"
				else
					error "[$command] $task_kind: invalid value for kind"
				fi
			fi

			echo "\$restore_path"
		SHELL
		;;
	*)
		error "$command: invalid command"
    ;;
esac
