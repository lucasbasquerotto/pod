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

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	msg="This project must not be in the '/' directory"
	echo -e "${RED}${msg}${NC}"
	exit 1
fi

command="${1:-}"

if [ -z "$command" ]; then
	echo -e "${RED}No command entered.${NC}"
	exit 1
fi

shift;

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
			"$pod_script_env_file" setup 
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
			"$pod_script_env_file" deploy 
		fi
		
		echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
		"$pod_script_env_file" up
		echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
		;;
	"setup")
		cd "$pod_full_dir/"
		"$pod_script_env_file" "setup:uploads"
		"$pod_script_env_file" "setup:db"
		"$pod_script_env_file" deploy 
		;;
	"setup:uploads")
		"$pod_script_env_file" up "$var_restore_service"

		echo -e "${CYAN}$(date '+%F %X') - $command - verify if uploads setup should be done${NC}"
		skip="$("$pod_script_env_file" "setup:uploads:verify")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="$command: value of the verification should be true or false - result: $skip"
			echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
			exit 1
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %X') - $command - skipping..."
		else
			if [ ! -z "$var_setup_local_uploads_zip_file" ] \
			|| [ ! -z "$var_setup_remote_uploads_zip_file" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_uploads_dir" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_uploads_file" ]; then

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" "setup:uploads:remote")"
			fi
		fi
		;;
	"setup:uploads:verify")
		dir_ls="$("$pod_script_env_file" exec-nontty "$var_restore_service" \
			find /"${var_uploads_service_dir}"/ -type f | wc -l)"

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
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		setup_uploads_zip_file=""
		restore_remote_src_uploads=""
		restore_local_dest_uploads=""

		if [ ! -z "$var_setup_local_uploads_zip_file" ]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
			setup_uploads_zip_file="$var_setup_local_uploads_zip_file"
		elif [ ! -z "$var_setup_remote_uploads_zip_file" ]; then
			setup_uploads_zip_file_name="uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s').zip"
			setup_uploads_zip_file="/$var_uploads_main_dir/$setup_uploads_zip_file_name"
		elif [ ! -z "$var_setup_remote_bucket_path_uploads_dir" ]; then
			backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_uploads_dir"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_uploads="s3://$backup_bucket_path"
		elif [ ! -z "$var_setup_remote_bucket_path_uploads_file" ]; then
			setup_uploads_zip_file_name="uploads-$key.zip"
			setup_uploads_zip_file="$var_uploads_main_dir/$setup_uploads_zip_file_name"

			backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_uploads_file"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_uploads="s3://$backup_bucket_path"
			restore_local_dest_uploads="/$setup_uploads_zip_file"
			restore_local_dest_uploads=$(echo "$restore_local_dest_uploads" | tr -s /)
		else
			echo -e "${RED}${command}: no source provided ${NC}"
			exit 1
		fi

		uploads_restore_specific_dir="$var_uploads_main_dir/uploads-$key"

		echo -e "${CYAN}$(date '+%F %X') - $command - $var_backup_service - restore${NC}"
		"$pod_script_env_file" up "$var_restore_service"
		"$pod_script_env_file" exec-nontty "$var_restore_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$var_uploads_main_dir"
			mkdir -p "/$var_uploads_main_dir"
		
			if [ ! -z "$var_setup_local_uploads_zip_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
			elif [ ! -z "$var_setup_remote_uploads_zip_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from remote dir${NC}"
				curl -L -o "$setup_uploads_zip_file" -k "$var_setup_remote_uploads_zip_file"
			elif [ ! -z "$var_setup_remote_bucket_path_uploads_file" ]; then
				msg="$command - restore uploads zip file from remote bucket"
				msg="\$msg [$restore_remote_src_uploads -> $restore_local_dest_uploads]"
				echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
			
				if [ "$var_use_aws_s3" = 'true' ]; then
					msg="$command - $var_backup_service - aws_s3 - copy bucket file to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 cp \
						--endpoint="$var_s3_endpoint" \
						"$restore_remote_src_uploads" "$restore_local_dest_uploads"
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - copy bucket file to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd cp "$restore_remote_src_uploads" "$restore_local_dest_uploads"
				else
					msg="$command - $var_backup_service - not able to copy bucket file to local path"
					echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
					exit 1
				fi
			fi

			if [ ! -z "$var_setup_remote_bucket_path_uploads_dir" ]; then
				msg="$command - restore uploads from remote bucket directly to uploads directory"
				msg="\$msg [$restore_remote_src_uploads -> /$var_uploads_service_dir]"
				echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
			
				if [ "$var_use_aws_s3" = 'true' ]; then
					msg="$command - $var_backup_service - aws_s3 - sync bucket dir to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$var_s3_endpoint" \
						"$restore_remote_src_uploads" "/$var_uploads_service_dir"
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - sync bucket dir to local path"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "$restore_remote_src_uploads" "/$var_uploads_service_dir"
				else
					msg="$command - $var_backup_service - not able to sync bucket dir to local path"
					echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
					exit 1
				fi
			else
				echo -e "${CYAN}$(date '+%F %X') - $command - uploads unzip${NC}"
				unzip "/$setup_uploads_zip_file" -d "/$uploads_restore_specific_dir"

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - main${NC}"
				cp -r  "/$uploads_restore_specific_dir/uploads"/. "/$var_uploads_service_dir/"
			fi
		SHELL
		;;
	"setup:db")
		# Restore the database
		"$pod_script_env_file" up "$var_restore_service" "$var_db_service"
		
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		echo -e "${CYAN}$(date '+%F %X') - $command - verify if db setup should be done${NC}"
		skip="$("$pod_script_env_file" "setup:db:verify")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="$command: value of the verification should be true or false - result: $skip"
			echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
			exit 1
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %X') - $command - skipping..."
		else
			if [ ! -z "$var_setup_local_db_file" ] \
			|| [ ! -z "$var_setup_remote_db_file" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_db_dir" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - remote${NC}"
				setup_db_sql_file="$("$pod_script_env_file" "setup:db:remote:file")"

				if [ -z "$setup_db_sql_file" ]; then
					msg="$command: unknown db file to restore"
					echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
					exit 1
				fi
				
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - local${NC}"
				"$pod_script_env_file" "setup:db:local:file" "$setup_db_sql_file"
			else
		    "$pod_script_env_file" "setup:db:new"
			fi
		fi
		;;
	"setup:db:remote:file")
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		if [ ! -z "$var_setup_local_db_file" ]; then
			setup_db_file="$var_setup_local_db_file"
		elif [ ! -z "$var_setup_remote_db_file" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$var_db_restore_dir/$setup_db_file_name"
		elif [ ! -z "$var_setup_remote_bucket_path_db_dir" ]; then
			setup_db_file="$var_db_restore_dir/$var_db_name.sql"

			backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_db_dir"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
		elif [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
			setup_db_file_name="db-$key.zip"
			setup_db_file="$var_db_restore_dir/$setup_db_file_name"

			backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_db_file"
			backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
			
			restore_remote_src_db="s3://$backup_bucket_path"
			restore_local_dest_db="/$setup_db_file"
			restore_local_dest_db=$(echo "$restore_local_dest_db" | tr -s /)
		else
			echo -e "${RED}${command}: no source provided ${NC}"
			exit 1
		fi

		extension=${setup_db_file##*.}

		if [ "$extension" = "zip" ]; then
			setup_db_sql_file="$var_db_restore_dir/$var_db_name.sql"
		else
			setup_db_sql_file="$setup_db_file"
		fi

		>&2  echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
		"$pod_script_env_file" up "$var_restore_service"
		"$pod_script_env_file" exec-nontty "$var_restore_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$var_db_restore_dir"
			mkdir -p "/$var_db_restore_dir"
		
			if [ ! -z "$var_setup_local_db_file" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - restore db from local file${NC}"
			elif [ ! -z "$var_setup_remote_db_file" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - restore db from remote file${NC}"
				curl -L -o "/$setup_db_file" -k "$var_setup_remote_db_file"
			elif [ ! -z "$var_setup_remote_bucket_path_db_dir" ]; then
				msg="$command - restore db from remote bucket dir"
				msg="\$msg [$restore_remote_src_db -> $var_db_restore_dir]"
				>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

				if [ "$var_use_aws_s3" = 'true' ]; then
					msg="$command - $var_backup_service - aws_s3 - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$var_s3_endpoint" \
						"$restore_remote_src_db" "/$var_db_restore_dir"
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - sync bucket db dir to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "$restore_remote_src_db" "/$var_db_restore_dir"
				else
					msg="$command - $var_backup_service - not able to sync bucket db dir to local path"
					>&2 echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
					exit 1
				fi
			elif [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
				msg="$command - restore db from remote bucket"
				msg="\$msg [$restore_remote_src_db -> $restore_local_dest_db]"
				>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

				if [ "$var_use_aws_s3" = 'true' ]; then
					msg="$command - $var_backup_service - aws_s3 - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 cp \
						--endpoint="$var_s3_endpoint" \
						"$restore_remote_src_db" "$restore_local_dest_db"
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - copy bucket file to local path"
					>&2 echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd cp "$restore_remote_src_db" "$restore_local_dest_db"
				else
					msg="$command - $var_backup_service - not able to copy bucket file to local path"
					echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
					exit 1
				fi
			else
				msg="$command - db file to restore not specified"
				echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
				exit 1
			fi

			if [ -z "$var_setup_remote_bucket_path_db_dir" ]; then
				rm -f "/$var_db_restore_dir/$var_db_name.sql"
			fi

			if [ "$extension" = "zip" ]; then
				>&2 echo -e "${CYAN}$(date '+%F %X') - $command - db unzip${NC}"
				>&2 unzip "/$setup_db_file" -d "/$var_db_restore_dir"
			fi
		SHELL
			
		echo "/$setup_db_sql_file"
		;;
	"backup")
		echo -e "${CYAN}$(date '+%F %X') - $command - started${NC}"

		if ! [[ $var_backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="\$msg (value=$var_backup_delete_old_days)"
			echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
			exit 1
		fi

		cd "$pod_full_dir/"
		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_dir="$var_main_backup_base_dir/$main_backup_name"
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		backup_bucket_prefix="$(echo "$backup_bucket_prefix" | tr -s /)"
		backup_bucket_uploads_sync_dir="$var_backup_bucket_name/$var_backup_bucket_path/$var_backup_bucket_uploads_sync_dir"
		backup_bucket_uploads_sync_dir="$(echo "$backup_bucket_uploads_sync_dir" | tr -s /)"
		backup_bucket_db_sync_dir="$var_backup_bucket_name/$var_backup_bucket_path/$var_backup_bucket_db_sync_dir"
		backup_bucket_db_sync_dir="$(echo "$backup_bucket_db_sync_dir" | tr -s /)"		

		echo -e "${CYAN}$(date '+%F %X') - $command - start needed services${NC}"
		"$pod_script_env_file" up "$var_db_service" "$var_backup_service"
	
		echo -e "${CYAN}$(date '+%F %X') - $command - create and clean directories${NC}"
		"$pod_script_env_file" exec-nontty "$var_backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$var_db_backup_dir"
			mkdir -p "/$var_db_backup_dir"

			rm -rf "/$var_uploads_main_dir"
			mkdir -p "/$var_uploads_main_dir"
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - db backup${NC}"
		"$pod_script_env_file" "backup:db:local"
	
		echo -e "${CYAN}$(date '+%F %X') - $command - main backup${NC}"
		"$pod_script_env_file" exec-nontty "$var_backup_service" /bin/bash <<-SHELL
			set -eou pipefail

			mkdir -p "/$main_backup_dir"

			if [ -z "$var_backup_bucket_uploads_sync_dir" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - uploads backup${NC}"
				cp -r "/$var_uploads_service_dir" "/$var_uploads_main_dir"
				cd '/$var_uploads_main_dir'
				zip -r uploads.zip ./*
				mv "/$var_uploads_main_dir/uploads.zip" "/$main_backup_dir/uploads.zip"
			fi

			if [ -z "$var_backup_bucket_db_sync_dir" ]; then
				zip -j "/$var_db_backup_dir/db.zip" "/$var_db_backup_dir/$var_db_name.sql"
				mv "/$var_db_backup_dir/db.zip" "/$main_backup_dir/db.zip"
			fi

			if [ ! -z "$var_backup_bucket_name" ]; then
				if [ "$var_use_aws_s3" = 'true' ]; then
					error_log_file="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log"

					if ! aws s3 --endpoint="$var_s3_endpoint" ls "s3://$var_backup_bucket_name" 2> "\$error_log_file"; then
						if grep -q 'NoSuchBucket' "\$error_log_file"; then
							msg="$command - $var_backup_service - aws_s3 - create bucket $var_backup_bucket_name"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3api create-bucket \
								--endpoint="$var_s3_endpoint" \
								--bucket "$var_backup_bucket_name" 
						fi
					fi

					msg="$command - $var_backup_service - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$var_s3_endpoint" \
						"/$var_main_backup_base_dir/" \
						"s3://$backup_bucket_prefix"

					if [ ! -z "$var_backup_bucket_uploads_sync_dir" ]; then
						msg="$command - $var_backup_service - aws_s3 - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$var_s3_endpoint" \
							"/$var_uploads_service_dir/" \
							"s3://$backup_bucket_uploads_sync_dir/"
					fi

					if [ ! -z "$var_backup_bucket_db_sync_dir" ]; then
						msg="$command - $var_backup_service - aws_s3 - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$var_s3_endpoint" \
							"/$var_db_backup_dir/" \
							"s3://$backup_bucket_db_sync_dir/"
					fi
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "/$var_main_backup_base_dir/" "s3://$backup_bucket_prefix"

					if [ ! -z "$var_backup_bucket_uploads_sync_dir" ]; then
						msg="$command - $var_backup_service - s3cmd - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$var_uploads_service_dir/" "s3://$backup_bucket_uploads_sync_dir/"
					fi

					if [ ! -z "$var_backup_bucket_db_sync_dir" ]; then
						msg="$command - $var_backup_service - s3cmd - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$var_db_backup_dir/" "s3://$backup_bucket_db_sync_dir/"
					fi
				else
					msg="$command - $var_backup_service - not able to sync local backup with bucket"
					echo -e "${YELLOW}\$(date '+%F %X') - \${msg}${NC}"
				fi
			fi

			find /$var_main_backup_base_dir/* -ctime +$var_backup_delete_old_days -delete;
			find /$var_main_backup_base_dir/* -maxdepth 0 -type d -ctime \
			  +$var_backup_delete_old_days -exec rm -rf {} \;
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;
	*)
		echo -e "${RED}Invalid command: $command ${NC}"
		exit 1
    ;;
esac

end="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f"|"setup"|"setup:uploads"|"setup:db"|"backup")
    echo -e "${CYAN}$(date '+%F %X') - $command - end${NC}"
    echo -e "${CYAN}$command - $start - $end${NC}"
    ;;
esac