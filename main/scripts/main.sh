#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function error {
		msg="$(date '+%F %X') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: $command: ${1:-}"
		>&2 echo -e "${RED}${msg}${NC}"
		exit 2
}

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	error "This project must not be in the '/' directory"
fi

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

case "$command" in
  "args:db")
    inner_cmd="${1:-}"

		if [ -z "$inner_cmd" ]; then
			error "[$command] command not specified"
		fi

    shift;
		;;
esac

args=( "$@" )

>&2 echo "args=${args[@]}"

die() { error "$*"; }  # complain to STDERR and exit with error
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		local_uploads_zip_file ) needs_arg; local_uploads_zip_file="$OPTARG" ;;
		remote_uploads_zip_file ) needs_arg; remote_uploads_zip_file="$OPTARG" ;;
		remote_bucket_path_uploads_dir ) needs_arg; remote_bucket_path_uploads_dir="$OPTARG" ;;
		remote_bucket_path_uploads_file ) needs_arg; remote_bucket_path_uploads_file="$OPTARG";;
		restore_service ) needs_arg; restore_service="$OPTARG" ;;
		uploads_service_dir ) needs_arg; uploads_service_dir="$OPTARG" ;;
		backup_bucket_name ) needs_arg; backup_bucket_name="$OPTARG" ;;
		backup_bucket_path ) needs_arg; backup_bucket_path="$OPTARG";;
		uploads_main_dir ) needs_arg; uploads_main_dir="$OPTARG";;
		backup_service ) needs_arg; backup_service="$OPTARG";;
		s3_endpoint ) needs_arg; s3_endpoint="$OPTARG";;
		use_aws_s3 ) needs_arg; use_aws_s3="$OPTARG";;
		use_s3cmd ) needs_arg; use_s3cmd="$OPTARG";;
		db_name ) needs_arg; db_name="$OPTARG"; >&2 echo "db_name=$db_name" ;;
		db_service ) needs_arg; db_service="$OPTARG" ;;
		db_user ) needs_arg; db_user="$OPTARG" ;;
		db_pass ) needs_arg; db_pass="$OPTARG";;
		db_backup_dir ) needs_arg; db_backup_dir="$OPTARG" ;;
		local_db_file ) needs_arg; local_db_file="$OPTARG" ;;
		remote_db_file ) needs_arg; remote_db_file="$OPTARG" ;;
		remote_bucket_path_db_dir ) needs_arg; remote_bucket_path_db_dir="$OPTARG" ;;
		remote_bucket_path_db_file ) needs_arg; remote_bucket_path_db_file="$OPTARG";;
		db_restore_dir ) needs_arg; db_restore_dir="$OPTARG";;
		backup_delete_old_days ) needs_arg; backup_delete_old_days="$OPTARG";;
		main_backup_base_dir ) needs_arg; main_backup_base_dir="$OPTARG";;
		backup_bucket_uploads_sync_dir ) needs_arg; backup_bucket_uploads_sync_dir="$OPTARG";;
		backup_bucket_db_sync_dir ) needs_arg; backup_bucket_db_sync_dir="$OPTARG";;
		db_sql_file ) needs_arg; db_sql_file="$OPTARG";;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

re_number='^[0-9]+$'

start="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f"|"setup"|"setup:uploads"|"setup:db"|"backup")
    echo -e "${CYAN}$(date '+%F %X') - $command - start${NC}"
    ;;
esac

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f")
		echo -e "${CYAN}$(date '+%F %X') - $command - prepare...${NC}"
		"$pod_script_env_file" prepare
		echo -e "${CYAN}$(date '+%F %X') - $command - build...${NC}"
		"$pod_script_env_file" build

		if [[ "$command" = @("migrate"|"m") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - setup...${NC}"
			"$pod_script_env_file" setup "${args[@]}"
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
			"$pod_script_env_file" deploy "${args[@]}" 
		fi
		
		echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
		"$pod_script_env_file" up
		echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
		;;
	"setup")
		cd "$pod_full_dir/"
		"$pod_script_env_file" "setup:uploads" "${args[@]}"
		"$pod_script_env_file" "setup:db" "${args[@]}"
		"$pod_script_env_file" deploy "${args[@]}" 
		;;
	"setup:uploads")
		"$pod_script_env_file" up "$restore_service"

		echo -e "${CYAN}$(date '+%F %X') - $command - verify if uploads setup should be done${NC}"
		skip="$("$pod_script_env_file" "setup:uploads:verify" "${args[@]}")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			error "$command: value of the verification should be true or false - result: $skip"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %X') - $command - skipping..."
		else
			if [ ! -z "$local_uploads_zip_file" ] \
			|| [ ! -z "$remote_uploads_zip_file" ] \
			|| [ ! -z "$remote_bucket_path_uploads_dir" ] \
			|| [ ! -z "$remote_bucket_path_uploads_file" ]; then

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" "setup:uploads:remote" "${args[@]}")"
			fi
		fi
		;;
	"setup:uploads:verify")
		dir_ls="$("$pod_script_env_file" exec-nontty "$restore_service" \
			find /"${uploads_service_dir}"/ -type f | wc -l)"

		if [ -z "$dir_ls" ]; then
			dir_ls="0"
		fi

		if [[ $dir_ls -ne 0 ]]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"setup:uploads:remote")		
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		setup_uploads_zip_file=""
		restore_remote_src_uploads=""
		restore_local_dest_uploads=""

		if [ ! -z "$local_uploads_zip_file" ]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
			setup_uploads_zip_file="$local_uploads_zip_file"
		elif [ ! -z "$remote_uploads_zip_file" ]; then
			setup_uploads_zip_file_name="uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s').zip"
			setup_uploads_zip_file="/$uploads_main_dir/$setup_uploads_zip_file_name"
		elif [ ! -z "$remote_bucket_path_uploads_dir" ]; then
			backup_bucket_path="$backup_bucket_prefix/$remote_bucket_path_uploads_dir"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_uploads="s3://$backup_bucket_path"
		elif [ ! -z "$remote_bucket_path_uploads_file" ]; then
			setup_uploads_zip_file_name="uploads-$key.zip"
			setup_uploads_zip_file="$uploads_main_dir/$setup_uploads_zip_file_name"

			backup_bucket_path="$backup_bucket_prefix/$remote_bucket_path_uploads_file"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_uploads="s3://$backup_bucket_path"
			restore_local_dest_uploads="/$setup_uploads_zip_file"
			restore_local_dest_uploads=$(echo "$restore_local_dest_uploads" | tr -s /)
		else
			error "${command}: no source provided"
		fi

		uploads_restore_specific_dir="$uploads_main_dir/uploads-$key"

		echo -e "${CYAN}$(date '+%F %X') - $command - $backup_service - restore${NC}"
		"$pod_script_env_file" up "$restore_service"
		"$pod_script_env_file" exec-nontty "$restore_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$uploads_main_dir"
			mkdir -p "/$uploads_main_dir"
		
			if [ ! -z "$local_uploads_zip_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
			elif [ ! -z "$remote_uploads_zip_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from remote dir${NC}"
				curl -L -o "$setup_uploads_zip_file" -k "$remote_uploads_zip_file"
			elif [ ! -z "$remote_bucket_path_uploads_file" ]; then
				msg="$command - restore uploads zip file from remote bucket"
				msg="\$msg [$restore_remote_src_uploads -> $restore_local_dest_uploads]"
				echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
			
				if [ "$use_aws_s3" = 'true' ]; then
					msg="$command - $backup_service - aws_s3 - copy bucket file to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 cp \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_uploads" "$restore_local_dest_uploads"
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - $backup_service - s3cmd - copy bucket file to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd cp "$restore_remote_src_uploads" "$restore_local_dest_uploads"
				else
					error "$command - $backup_service - not able to copy bucket file to local path"
				fi
			fi

			if [ ! -z "$remote_bucket_path_uploads_dir" ]; then
				msg="$command - restore uploads from remote bucket directly to uploads directory"
				msg="\$msg [$restore_remote_src_uploads -> /$uploads_service_dir]"
				echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
			
				if [ "$use_aws_s3" = 'true' ]; then
					msg="$command - $backup_service - aws_s3 - sync bucket dir to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_uploads" "/$uploads_service_dir"
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - $backup_service - s3cmd - sync bucket dir to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "$restore_remote_src_uploads" "/$uploads_service_dir"
				else
					error "$command - $backup_service - not able to sync bucket dir to local path"
				fi
			else
				echo -e "${CYAN}$(date '+%F %X') - $command - uploads unzip${NC}"
				unzip "/$setup_uploads_zip_file" -d "/$uploads_restore_specific_dir"

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - main${NC}"
				cp -r  "/$uploads_restore_specific_dir/uploads"/. "/$uploads_service_dir/"
			fi
		SHELL
		;;
	"setup:db")
		# Restore the database
		"$pod_script_env_file" up "$restore_service" "$db_service"
		
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		echo -e "${CYAN}$(date '+%F %X') - $command - verify if db setup should be done${NC}"
		skip="$("$pod_script_env_file" "args:db" "setup:db:verify" "${args[@]}")"
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			error "$command: value of the verification should be true or false - result: $skip"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %X') - $command - skipping..."
		else
			if [ ! -z "$local_db_file" ] \
			|| [ ! -z "$remote_db_file" ] \
			|| [ ! -z "$remote_bucket_path_db_dir" ] \
			|| [ ! -z "$remote_bucket_path_db_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" "args:db" "setup:db:remote:file" "${args[@]}")"

				if [ -z "$setup_db_sql_file" ]; then
					error "$command: unknown db file to restore"
				fi
				
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - local${NC}"
				"$pod_script_env_file" "args:db" "setup:db:local:file" "${args[@]}" \
          --db_sql_file="$setup_db_sql_file"
			else
		    "$pod_script_env_file" "args:db" "setup:db:new"
			fi
		fi
		;;
	"setup:db:remote:file")
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		if [ ! -z "$local_db_file" ]; then
			setup_db_file="$local_db_file"
		elif [ ! -z "$remote_db_file" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$db_restore_dir/$setup_db_file_name"
		elif [ ! -z "$remote_bucket_path_db_dir" ]; then
			setup_db_file="$db_restore_dir/$db_name.sql"

			backup_bucket_path="$backup_bucket_prefix/$remote_bucket_path_db_dir"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
		elif [ ! -z "$remote_bucket_path_db_file" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$db_restore_dir/$setup_db_file_name"

			backup_bucket_path="$backup_bucket_prefix/$remote_bucket_path_db_file"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
			restore_local_dest_db="/$setup_db_file"
			restore_local_dest_db=$(echo "$restore_local_dest_db" | tr -s /)
		else
			error "${command}: no source provided"
		fi

		extension=${setup_db_file##*.}

		if [ "$extension" = "zip" ]; then
			setup_db_sql_file="$db_restore_dir/$db_name.sql"
		else
			setup_db_sql_file="$setup_db_file"
		fi

		>&2  echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
		"$pod_script_env_file" up "$restore_service"
		"$pod_script_env_file" exec-nontty "$restore_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$db_restore_dir"
			mkdir -p "/$db_restore_dir"
		
			if [ ! -z "$local_db_file" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - restore db from local file${NC}"
			elif [ ! -z "$remote_db_file" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - restore db from remote file${NC}"
				curl -L -o "/$setup_db_file" -k "$remote_db_file"
			elif [ ! -z "$remote_bucket_path_db_dir" ]; then
				msg="$command - restore db from remote bucket dir"
				msg="\$msg [$restore_remote_src_db -> $db_restore_dir]"
				>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

				if [ "$use_aws_s3" = 'true' ]; then
					msg="$command - $backup_service - aws_s3 - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_db" "/$db_restore_dir"
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - $backup_service - s3cmd - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "$restore_remote_src_db" "/$db_restore_dir"
				else
					error "$command - $backup_service - not able to sync bucket db dir to local path"
				fi
			elif [ ! -z "$remote_bucket_path_db_file" ]; then
				msg="$command - restore db from remote bucket"
				msg="\$msg [$restore_remote_src_db -> $restore_local_dest_db]"
				>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

				if [ "$use_aws_s3" = 'true' ]; then
					msg="$command - $backup_service - aws_s3 - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 cp \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_db" "$restore_local_dest_db"
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - $backup_service - s3cmd - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd cp "$restore_remote_src_db" "$restore_local_dest_db"
				else
					error "$command - $backup_service - not able to copy bucket file to local path"
				fi
			else
				error "$command - db file to restore not specified"
			fi

			if [ -z "$remote_bucket_path_db_dir" ]; then
				rm -f "/$db_restore_dir/$db_name.sql"
			fi

			if [ "$extension" = "zip" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - db unzip${NC}"
				>&2 unzip "/$setup_db_file" -d "/$db_restore_dir"
			fi
		SHELL
			
		echo "/$setup_db_sql_file"
		;;
	"backup")
		echo -e "${CYAN}$(date '+%F %X') - $command - started${NC}"

		if ! [[ $backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="\$msg (value=$backup_delete_old_days)"
			error "$msg"
		fi

		cd "$pod_full_dir/"
		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_dir="$main_backup_base_dir/$main_backup_name"
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		backup_bucket_prefix="$(echo "$backup_bucket_prefix" | tr -s /)"
		backup_bucket_uploads_sync_dir_full="$backup_bucket_name/$backup_bucket_path/$backup_bucket_uploads_sync_dir"
		backup_bucket_uploads_sync_dir_full="$(echo "$backup_bucket_uploads_sync_dir_full" | tr -s /)"
		backup_bucket_db_sync_dir_full="$backup_bucket_name/$backup_bucket_path/$backup_bucket_db_sync_dir"
		backup_bucket_db_sync_dir_full="$(echo "$backup_bucket_db_sync_dir_full" | tr -s /)"		

		echo -e "${CYAN}$(date '+%F %X') - $command - start needed services${NC}"
		"$pod_script_env_file" up "$db_service" "$backup_service"
	
		echo -e "${CYAN}$(date '+%F %X') - $command - create and clean directories${NC}"
		"$pod_script_env_file" exec-nontty "$backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$db_backup_dir"
			mkdir -p "/$db_backup_dir"

			rm -rf "/$uploads_main_dir"
			mkdir -p "/$uploads_main_dir"
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - db backup${NC}"
		"$pod_script_env_file" "args:db" "backup:db:local" "${args[@]}"
	
		echo -e "${CYAN}$(date '+%F %X') - $command - main backup${NC}"
		"$pod_script_env_file" exec-nontty "$backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			mkdir -p "/$main_backup_dir"

			if [ -z "$backup_bucket_uploads_sync_dir" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - uploads backup${NC}"
				cp -r "/$uploads_service_dir" "/$uploads_main_dir"
				cd '/$uploads_main_dir'
				zip -r uploads.zip ./*
				mv "/$uploads_main_dir/uploads.zip" "/$main_backup_dir/uploads.zip"
			fi

			if [ -z "$backup_bucket_db_sync_dir" ]; then
				zip -j "/$db_backup_dir/db.zip" "/$db_backup_dir/$db_name.sql"
				mv "/$db_backup_dir/db.zip" "/$main_backup_dir/db.zip"
			fi

			if [ ! -z "$backup_bucket_name" ]; then
				if [ "$use_aws_s3" = 'true' ]; then
					error_log_file="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log"

					if ! aws s3 --endpoint="$s3_endpoint" ls "s3://$backup_bucket_name" 2> "\$error_log_file"; then
						if grep -q 'NoSuchBucket' "\$error_log_file"; then
							msg="$command - $backup_service - aws_s3 - create bucket $backup_bucket_name"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3api create-bucket \
								--endpoint="$s3_endpoint" \
								--bucket "$backup_bucket_name" 
						fi
					fi

					msg="$command - $backup_service - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"/$main_backup_base_dir/" \
						"s3://$backup_bucket_prefix"

					if [ ! -z "$backup_bucket_uploads_sync_dir" ]; then
						msg="$command - $backup_service - aws_s3 - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$uploads_service_dir/" \
							"s3://$backup_bucket_uploads_sync_dir_full/"
					fi

					if [ ! -z "$backup_bucket_db_sync_dir" ]; then
						msg="$command - $backup_service - aws_s3 - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$db_backup_dir/" \
							"s3://$backup_bucket_db_sync_dir_full/"
					fi
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - $backup_service - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "/$main_backup_base_dir/" "s3://$backup_bucket_prefix"

					if [ ! -z "$backup_bucket_uploads_sync_dir" ]; then
						msg="$command - $backup_service - s3cmd - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$uploads_service_dir/" "s3://$backup_bucket_uploads_sync_dir_full/"
					fi

					if [ ! -z "$backup_bucket_db_sync_dir" ]; then
						msg="$command - $backup_service - s3cmd - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$db_backup_dir/" "s3://$backup_bucket_db_sync_dir_full/"
					fi
				else
					msg="$command - $backup_service - not able to sync local backup with bucket"
					echo -e "${YELLOW}\$(date '+%F %X') - \${msg}${NC}"
				fi
			fi

			find /$main_backup_base_dir/* -ctime +$backup_delete_old_days -delete;
			find /$main_backup_base_dir/* -maxdepth 0 -type d -ctime \
			  +$backup_delete_old_days -exec rm -rf {} \;
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;
  "args:db")
    opts=()

    if [ ! -z "${db_name:-}" ]; then
      opts+=( "--db_name=${db_name:-}" )
    fi
    if [ ! -z "${db_service:-}" ]; then
      opts+=( "--db_service=${db_service:-}" )
    fi
    if [ ! -z "${db_user:-}" ]; then
      opts+=( "--db_user=${db_user:-}" )
    fi
    if [ ! -z "${db_pass:-}" ]; then
      opts+=( "--db_pass=${db_pass:-}" )
    fi
    if [ ! -z "${db_backup_dir:-}" ]; then
      opts+=( "--db_backup_dir=${db_backup_dir:-}" )
    fi
    if [ ! -z "${db_sql_file:-}" ]; then
      opts+=( "--db_sql_file=${db_sql_file:-}" )
    fi

		"$pod_script_env_file" "$inner_cmd" "${opts[@]}"
    ;;
	*)
		error "$command: invalid command"
    ;;
esac

end="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f"|"setup"|"setup:uploads"|"setup:db"|"backup")
    echo -e "${CYAN}$(date '+%F %X') - $command - end${NC}"
    echo -e "${CYAN}$command - $start - $end${NC}"
    ;;
esac