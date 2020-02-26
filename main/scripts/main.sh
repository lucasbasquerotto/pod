#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"
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

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	error "This project must not be in the '/' directory"
fi

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=( "$@" )

die() { error "$*"; }  # complain to STDERR and exit with error
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		setup_task_names ) needs_arg; setup_task_names="$OPTARG";;
		setup_task_name ) needs_arg; setup_task_name="$OPTARG";; 
		setup_task_name_verify ) needs_arg; setup_task_name_verify="$OPTARG";; 
		setup_task_name_remote ) needs_arg; setup_task_name_remote="$OPTARG";; 
		setup_task_name_local ) needs_arg; setup_task_name_local="$OPTARG";; 
		setup_task_name_new ) needs_arg; setup_task_name_new="$OPTARG";; 
		setup_local_zip_file ) needs_arg; setup_local_zip_file="$OPTARG" ;;
		setup_remote_zip_file ) needs_arg; setup_remote_zip_file="$OPTARG" ;;
		setup_remote_bucket_path_dir ) needs_arg; setup_remote_bucket_path_dir="$OPTARG" ;;
		setup_remote_bucket_path_file ) needs_arg; setup_remote_bucket_path_file="$OPTARG";;
		setup_dest_dir ) needs_arg; setup_dest_dir="$OPTARG";;
		setup_tmp_dir ) needs_arg; setup_tmp_dir="$OPTARG" ;;
		setup_kind ) needs_arg; setup_kind="$OPTARG";;
		setup_zip_inner_dir ) needs_arg; setup_zip_inner_dir="$OPTARG";;
		setup_zip_inner_file ) needs_arg; setup_zip_inner_file="$OPTARG";;
		setup_name ) needs_arg; setup_name="$OPTARG";;
		setup_bucket_name ) needs_arg; setup_bucket_name="$OPTARG" ;;
		setup_bucket_path ) needs_arg; setup_bucket_path="$OPTARG";;
		setup_service ) needs_arg; setup_service="$OPTARG" ;;

		backup_task_names ) needs_arg; backup_task_names="$OPTARG";;
		backup_task_name ) needs_arg; backup_task_name="$OPTARG";;
		backup_bucket_name ) needs_arg; backup_bucket_name="$OPTARG" ;;
		backup_bucket_path ) needs_arg; backup_bucket_path="$OPTARG";;
		backup_service ) needs_arg; backup_service="$OPTARG";;

		s3_endpoint ) needs_arg; s3_endpoint="$OPTARG";;
		use_aws_s3 ) needs_arg; use_aws_s3="$OPTARG";;
		use_s3cmd ) needs_arg; use_s3cmd="$OPTARG";;
		db_name ) needs_arg; db_name="$OPTARG";;
		db_service ) needs_arg; db_service="$OPTARG" ;;
		local_db_file ) needs_arg; local_db_file="$OPTARG" ;;
		remote_db_file ) needs_arg; remote_db_file="$OPTARG" ;;
		remote_bucket_path_db_dir ) needs_arg; remote_bucket_path_db_dir="$OPTARG" ;;
		remote_bucket_path_db_file ) needs_arg; remote_bucket_path_db_file="$OPTARG";;
		db_restore_dir ) needs_arg; db_restore_dir="$OPTARG";;
		backup_delete_old_days ) needs_arg; backup_delete_old_days="$OPTARG";;
		main_backup_base_dir ) needs_arg; main_backup_base_dir="$OPTARG";;
		backup_bucket_sync_dir ) needs_arg; backup_bucket_sync_dir="$OPTARG";;    
		backup_task_name_local ) needs_arg; backup_task_name_local="$OPTARG";;  
		backup_kind ) needs_arg; backup_kind="$OPTARG";;  
		backup_name ) needs_arg; backup_name="$OPTARG";;  
		backup_service_dir ) needs_arg; backup_service_dir="$OPTARG";;  
		backup_intermediate_dir ) needs_arg; backup_intermediate_dir="$OPTARG";; 
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

function run_tasks {
  task_names="${1:-}" 
  task_cmd_base_name="${2:-}" 
  task_parameter_name="${3:-}" 

  if [ ! -z "${task_names:-}" ]; then
    IFS=',' read -r -a tmp <<< "${task_names}"
    arr=("${tmp[@]}")

    for task_name in "${arr[@]}"; do
      "$pod_script_env_file" "$task_cmd_base_name:$task_name" "${args[@]}" \
        "--$task_parameter_name=$task_name"
    done
  fi
}

start="$(date '+%F %T')"

case "$command" in
	"migrate"|"update"|"fast-update"|"setup"|"fast-setup"|"setup:uploads"|"setup:db"|"backup")
    echo -e "${CYAN}$(date '+%F %T') - $command - start${NC}"
    ;;
esac

case "$command" in
	"migrate"|"update"|"fast-update")
		echo -e "${CYAN}$(date '+%F %T') - $command - prepare...${NC}"
		"$pod_script_env_file" prepare
		echo -e "${CYAN}$(date '+%F %T') - $command - build...${NC}"
		"$pod_script_env_file" build

		if [[ "$command" = @("migrate"|"m") ]]; then
			echo -e "${CYAN}$(date '+%F %T') - $command - setup...${NC}"
			"$pod_script_env_file" setup "${args[@]}"
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %T') - $command - deploy...${NC}"
			"$pod_script_env_file" deploy "${args[@]}" 
		fi
		
		echo -e "${CYAN}$(date '+%F %T') - $command - run...${NC}"
		"$pod_script_env_file" up
		echo -e "${CYAN}$(date '+%F %T') - $command - ended${NC}"
		;;
	"setup"|"fast-setup")    
		run_tasks "${setup_task_names:-}" "setup:task" "setup_task_name"

    if [ "$command" = "setup" ]; then
      "$pod_script_env_file" deploy "${args[@]}" 
    fi
		;;
	"setup:default")
		echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - start needed services${NC}"
		"$pod_script_env_file" up "$setup_service"

		msg="verify if the setup should be done"
		echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - $msg ${NC}"
		skip="$("$pod_script_env_file" "${setup_task_name_verify}" "${args[@]}")"
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$command ($setup_task_name): $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($setup_task_name) - skipping..."
		elif [ ! -z "${setup_local_zip_file:-}" ] \
			|| [ ! -z "${setup_remote_zip_file:-}" ] \
			|| [ ! -z "${setup_remote_bucket_path_dir:-}" ] \
			|| [ ! -z "${setup_remote_bucket_path_file:-}" ]; then

			echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - restore - remote${NC}"
			setup_restored_file="$("$pod_script_env_file" \
				"${setup_task_name_remote}" "${args[@]}")"

			if [ -z "${setup_restored_file:-}" ]; then
				error "$command ($setup_task_name): unknown file to restore"
			fi
			
			if [ ! -z "${setup_task_name_local:-}" ]; then
				echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - restore - local${NC}"
				"$pod_script_env_file" "${setup_task_name_local}" \
					"${args[@]}" --setup_restored_path="$setup_restored_file"
			fi
		else
			"$pod_script_env_file" "${setup_task_name_new}"
		fi
		;;
	"setup:verify")
		msg="verify if the directory ${setup_dest_dir:-} is empty"
		>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - $msg ${NC}"

		dir_ls="$("$pod_script_env_file" exec-nontty "$setup_service" \
			find /"${setup_dest_dir}"/ -type f | wc -l)"

		if [ -z "$dir_ls" ]; then
			dir_ls="0"
		fi

		if [[ $dir_ls -ne 0 ]]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"setup:remote")		
		setup_bucket_prefix="$setup_bucket_name/$setup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		setup_zip_file=""
		restore_remote_src=""
		restore_local_dest=""

		if [ ! -z "${setup_local_zip_file:-}" ]; then
			setup_zip_file="$setup_local_zip_file"
		elif [ ! -z "${setup_remote_zip_file:-}" ]; then
			setup_zip_file_name="$setup_name-$key.zip"
			setup_zip_file="/$setup_tmp_dir/$setup_zip_file_name"
		elif [ ! -z "${setup_remote_bucket_path_dir:-}" ]; then
			setup_bucket_path="$setup_bucket_prefix/$remote_bucket_path_dir"
			setup_bucket_path=$(echo "$setup_bucket_path" | tr -s /)
			
			restore_remote_src="s3://$setup_bucket_path"
		elif [ ! -z "${setup_remote_bucket_path_file:-}" ]; then
			setup_zip_file_name="$setup_name-$key.zip"
			setup_zip_file="$setup_tmp_dir/$setup_zip_file_name"

			setup_bucket_path="$setup_bucket_prefix/$setup_remote_bucket_path_file"
			setup_bucket_path=$(echo "$setup_bucket_path" | tr -s /)
			
			restore_remote_src="s3://$setup_bucket_path"
			restore_local_dest="/$setup_zip_file"
			restore_local_dest=$(echo "$restore_local_dest" | tr -s /)
		else
			error "$command ($setup_task_name): no source provided"
		fi

		>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - $setup_service - restore${NC}"
		>&2 "$pod_script_env_file" up "$setup_service"
		"$pod_script_env_file" exec-nontty "$setup_service" /bin/bash <<-SHELL
			set -eou pipefail

			>&2 rm -rf "/$setup_tmp_dir"
			>&2 mkdir -p "/$setup_tmp_dir"
		
			if [ ! -z "${setup_local_zip_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - restore from local dir${NC}"
			elif [ ! -z "${setup_remote_zip_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - restore from remote dir${NC}"
				>&2 curl -L -o "$setup_zip_file" -k "$setup_remote_zip_file"
			elif [ ! -z "${setup_remote_bucket_path_file:-}" ]; then
				msg="$command ($setup_task_name) - restore zip file from remote bucket"
				msg="\$msg [$restore_remote_src -> $restore_local_dest]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
			
				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command ($setup_task_name) - $setup_service - aws_s3 - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 aws s3 cp \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src" "$restore_local_dest"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command ($setup_task_name) - $setup_service - s3cmd - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 s3cmd cp "$restore_remote_src" "$restore_local_dest"
				else
					error "$command ($setup_task_name) - $setup_service - not able to copy bucket file to local path"
				fi
			fi

			if [ ! -z "${setup_remote_bucket_path_dir:-}" ]; then
				msg="$command ($setup_task_name) - restore from remote bucket directly to local directory"
				msg="\$msg [$restore_remote_src -> /$setup_dest_dir]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
			
				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command ($setup_task_name) - $setup_service - aws_s3 - sync bucket dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 aws s3 sync \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src" "/$setup_dest_dir"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command ($setup_task_name) - $setup_service - s3cmd - sync bucket dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					>&2 s3cmd sync "$restore_remote_src" "/$setup_dest_dir"
				else
					error "$command ($setup_task_name) - $setup_service - not able to sync bucket dir to local path"
				fi

				echo "/$setup_dest_dir"
			else
				msg="unzip at $setup_tmp_dir"
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - \$msg${NC}"

				if [ "$setup_kind" = "dir" ]; then
					msg="unzip to directory $setup_tmp_dir"
					>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - \$msg${NC}"
					>&2 unzip "/$setup_zip_file" -d "/$setup_tmp_dir"

					>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - restore - main${NC}"
					>&2 cp -r  "/$setup_tmp_dir/${setup_zip_inner_dir:-}"/. "/$setup_dest_dir/"
					
					echo "/$setup_dest_dir"
				elif [ "$setup_kind" = "file" ]; then
					msg="unzip to directory $setup_dest_dir"
					>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($setup_task_name) - \$msg${NC}"
					>&2 unzip "/$setup_zip_file" -d "/$setup_dest_dir"

					echo "/$setup_dest_dir/${setup_zip_inner_file:-}"
				else
					error "[$command] $setup_kind: invalid value for setup_kind"
				fi
			fi
		SHELL
		;;
	"setup:uploads")
		"$pod_script_env_file" up "$setup_service"

		echo -e "${CYAN}$(date '+%F %T') - $command ($uploads_task_name) - verify if uploads setup should be done${NC}"
		skip="$("$pod_script_env_file" "setup:uploads:verify:$uploads_task_name" "${args[@]}")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			error "$command ($uploads_task_name): value of the verification should be true or false - result: $skip"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($uploads_task_name) - skipping..."
		else
			if [ ! -z "${local_uploads_zip_file:-}" ] \
			|| [ ! -z "${remote_uploads_zip_file:-}" ] \
			|| [ ! -z "${remote_bucket_path_uploads_dir:-}" ] \
			|| [ ! -z "${remote_bucket_path_uploads_file:-}" ]; then

				echo -e "${CYAN}$(date '+%F %T') - $command ($uploads_task_name) - uploads restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" \
          "setup:uploads:remote:$uploads_task_name" "${args[@]}")"
			fi
		fi
		;;
	"setup:db")
		# Restore the database
		"$pod_script_env_file" up "$setup_service" "$db_service"
		
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - verify if db setup should be done${NC}"
		skip="$("$pod_script_env_file" "setup:db:verify:${db_task_name}" "${args[@]}")"
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			error "$command ($db_task_name): value of the verification should be true or false - result: $skip"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($db_task_name) - skipping..."
		else
			if [ ! -z "${local_db_file:-}" ] \
			|| [ ! -z "${remote_db_file:-}" ] \
			|| [ ! -z "${remote_bucket_path_db_dir:-}" ] \
			|| [ ! -z "${remote_bucket_path_db_file:-}" ]; then
				echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - db restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" \
          "setup:db:remote:file:${db_task_name}" "${args[@]}")"

				if [ -z "${setup_db_sql_file:-}" ]; then
					error "$command ($db_task_name): unknown db file to restore"
				fi
				
				echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - db restore - local${NC}"
				"$pod_script_env_file" "setup:db:local:file:${db_task_name}" \
          "${args[@]}" --db_sql_file="$setup_db_sql_file"
			else
		    "$pod_script_env_file" "setup:db:new:${db_task_name}"
			fi
		fi
		;;
	"setup:db:remote:file")
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		if [ ! -z "${local_db_file:-}" ]; then
			setup_db_file="${local_db_file:-}"
		elif [ ! -z "${remote_db_file:-}" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$db_restore_dir/$setup_db_file_name"
		elif [ ! -z "${remote_bucket_path_db_dir:-}" ]; then
			setup_db_file="$db_restore_dir/$db_name.sql"

			backup_bucket_path="$backup_bucket_prefix/${remote_bucket_path_db_dir:-}"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
		elif [ ! -z "${remote_bucket_path_db_file:-}" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$db_restore_dir/$setup_db_file_name"

			backup_bucket_path="$backup_bucket_prefix/${remote_bucket_path_db_file:-}"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
			restore_local_dest_db="/$setup_db_file"
			restore_local_dest_db=$(echo "$restore_local_dest_db" | tr -s /)
		else
			error "$command ($db_task_name): no source provided"
		fi

		extension=${setup_db_file##*.}

		if [ "$extension" = "zip" ]; then
			setup_db_sql_file="$db_restore_dir/$db_name.sql"
		else
			setup_db_sql_file="$setup_db_file"
		fi

		>&2  echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - create and clean the directories${NC}"
		"$pod_script_env_file" up "$setup_service"
		"$pod_script_env_file" exec-nontty "$setup_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$db_restore_dir"
			mkdir -p "/$db_restore_dir"
		
			if [ ! -z "${local_db_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - restore db from local file${NC}"
			elif [ ! -z "${remote_db_file:-}" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - restore db from remote file${NC}"
				curl -L -o "/$setup_db_file" -k "${remote_db_file:-}"
			elif [ ! -z "${remote_bucket_path_db_dir:-}" ]; then
				msg="$command ($db_task_name) - restore db from remote bucket dir"
				msg="\$msg [$restore_remote_src_db -> $db_restore_dir]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"

				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command ($db_task_name) - $backup_service - aws_s3 - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_db" "/$db_restore_dir"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command ($db_task_name) - $backup_service - s3cmd - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					s3cmd sync "$restore_remote_src_db" "/$db_restore_dir"
				else
					error "$command ($db_task_name) - $backup_service - not able to sync bucket db dir to local path"
				fi
			elif [ ! -z "${remote_bucket_path_db_file:-}" ]; then
				msg="$command ($db_task_name) - restore db from remote bucket"
				msg="\$msg [$restore_remote_src_db -> $restore_local_dest_db]"
				>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"

				if [ "${use_aws_s3:-}" = 'true' ]; then
					msg="$command ($db_task_name) - $backup_service - aws_s3 - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					aws s3 cp \
						--endpoint="$s3_endpoint" \
						"$restore_remote_src_db" "$restore_local_dest_db"
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command ($db_task_name) - $backup_service - s3cmd - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					s3cmd cp "$restore_remote_src_db" "$restore_local_dest_db"
				else
					error "$command ($db_task_name) - $backup_service - not able to copy bucket file to local path"
				fi
			else
				error "$command ($db_task_name) - db file to restore not specified"
			fi

			if [ -z "${remote_bucket_path_db_dir:-}" ]; then
				rm -f "/$db_restore_dir/$db_name.sql"
			fi

			if [ "$extension" = "zip" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($db_task_name) - db unzip${NC}"
				>&2 unzip "/$setup_db_file" -d "/$db_restore_dir"
			fi
		SHELL
			
		echo "/$setup_db_sql_file"
		;;
	"backup")	
		run_tasks "${backup_task_names:-}" "backup:task" "backup_task_name"
		;;  
	"backup:default")
		echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - started${NC}"

    re_number='^[0-9]+$'

		if ! [[ $backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="\$msg (value=$backup_delete_old_days)"
			error "$msg"
		fi

		echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - start needed services${NC}"
		"$pod_script_env_file" up "$backup_service"

		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_dir="$main_backup_base_dir/$main_backup_name"
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		backup_bucket_prefix="$(echo "$backup_bucket_prefix" | tr -s /)"
		backup_bucket_sync_dir_full="$backup_bucket_name/$backup_bucket_path/$backup_bucket_sync_dir"
		backup_bucket_sync_dir_full="$(echo "$backup_bucket_sync_dir_full" | tr -s /)"

		echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - create and clean directories${NC}"
		"$pod_script_env_file" exec-nontty "$backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$backup_intermediate_dir"
			mkdir -p "/$backup_intermediate_dir"
		SHELL

		if [ ! -z "$backup_task_name_local" ]; then
			echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - db backup${NC}"
			"$pod_script_env_file" "$backup_task_name_local" "${args[@]}"
		fi

		echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - main backup${NC}"
		"$pod_script_env_file" exec-nontty "$backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			mkdir -p "/$main_backup_dir"

			if [ -z "$backup_bucket_sync_dir" ]; then
			  if [ "$backup_kind" = "dir" ]; then
					echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - backup directpry ($backup_service_dir)${NC}"
					cp -r "/$backup_service_dir" "/$backup_intermediate_dir"
					cd "/$backup_intermediate_dir"
					zip -r $backup_name.zip ./*
					mv "/$backup_intermediate_dir/$backup_name.zip" "/$main_backup_dir/$backup_name.zip"
				elif [ "$backup_kind" = "file" ]; then
					zip -j "/$backup_intermediate_dir/$backup_name.zip" "/$backup_service_dir/$backup_src_file"
					mv "/$backup_intermediate_dir/$backup_name.zip" "/$main_backup_dir/$backup_name.zip"
				else
					error "[$command ($backup_task_name)] $backup_kind: backup_kind invalid value"
				fi
			fi

			if [ ! -z "$backup_bucket_name" ]; then
				if [ "${use_aws_s3:-}" = 'true' ]; then
					error_log_file="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log"

					if ! aws s3 --endpoint="$s3_endpoint" ls "s3://$backup_bucket_name" 2> "\$error_log_file"; then
						if grep -q 'NoSuchBucket' "\$error_log_file"; then
							msg="$command ($backup_task_name) - $backup_service - aws_s3 - create bucket $backup_bucket_name"
							echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
							aws s3api create-bucket \
								--endpoint="$s3_endpoint" \
								--bucket "$backup_bucket_name" 
						fi
					fi

					msg="$command ($backup_task_name) - $backup_service - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"/$main_backup_base_dir/" \
						"s3://$backup_bucket_prefix"

					if [ ! -z "$backup_bucket_sync_dir" ]; then
						msg="$command ($backup_task_name) - $backup_service - aws_s3 - sync local directory with bucket"
						echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$backup_service_dir/" \
							"s3://$backup_bucket_sync_dir_full/"
					fi
				elif [ "${use_s3cmd:-}" = 'true' ]; then
					msg="$command ($backup_task_name) - $backup_service - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
					s3cmd sync "/$main_backup_base_dir/" "s3://$backup_bucket_prefix"

					if [ ! -z "$backup_bucket_sync_dir" ]; then
						msg="$command ($backup_task_name) - $backup_service - s3cmd - sync local directory with bucket"
						echo -e "${CYAN}\$(date '+%F %T') - \${msg}${NC}"
						s3cmd sync "/$backup_service_dir/" "s3://$backup_bucket_sync_dir_full/"
					fi
				else
					msg="$command ($backup_task_name) - $backup_service - not able to sync local backup with bucket"
					echo -e "${YELLOW}\$(date '+%F %T') - \${msg}${NC}"
				fi
			fi

			find /$main_backup_base_dir/* -ctime +$backup_delete_old_days -delete;
			find /$main_backup_base_dir/* -maxdepth 0 -type d -ctime \
				+$backup_delete_old_days -exec rm -rf {} \;
		SHELL

		echo -e "${CYAN}$(date '+%F %T') - $command ($backup_task_name) - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;  
	*)
		error "$command: invalid command"
    ;;
esac

end="$(date '+%F %T')"

case "$command" in
	"migrate"|"update"|"fast-update"|"setup"|"fast-setup"|"setup:uploads"|"setup:db"|"backup")
    echo -e "${CYAN}$(date '+%F %T') - $command - end${NC}"
    echo -e "${CYAN}$command - $start - $end${NC}"
    ;;
esac