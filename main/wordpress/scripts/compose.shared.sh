#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_full_dir="$POD_FULL_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

scripts_full_dir="${pod_layer_dir}/${var_scripts_dir}"

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
	echo -e "${RED}No command entered (env - shared).${NC}"
	exit 1
fi

shift;

re_number='^[0-9]+$'

start="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f"|"setup"|"setup:uploads"|"setup:db"|"setup:db:mysql"|"backup"|"backup:db:mysql")
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
		# Restore the uploaded files
    cd "$pod_full_dir"
		"$pod_script_env_file" up "$var_restore_service"
		
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		setup_uploads_zip_file=""
		restore_remote_src_uploads=""
		restore_local_dest_uploads=""

		dir_ls="$("$pod_script_env_file" exec-nontty "$var_restore_service" \
			find /${var_uploads_service_dir}/ -type f | wc -l)"

		if [ -z "$dir_ls" ]; then
			dir_ls="0"
		fi

		if [[ $dir_ls -ne 0 ]]; then
			msg="There are already uploaded files restored, skipping phase..."
			echo -e "${CYAN}$(date '+%F %X') - ${msg}${NC}"
		else
			if [ ! -z "$var_setup_local_uploads_zip_file" ] \
			|| [ ! -z "$var_setup_remote_uploads_zip_file" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_uploads_dir" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_uploads_file" ]; then

				if [ ! -z "$var_setup_local_uploads_zip_file" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
					setup_uploads_zip_file="$var_setup_local_uploads_zip_file"
				elif [ ! -z "$var_setup_remote_uploads_zip_file" ]; then
					setup_uploads_zip_file_name="uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s').zip"
					setup_uploads_zip_file="/$var_uploads_main_dir/$setup_uploads_zip_file_name"
				elif [ ! -z "$var_setup_remote_bucket_path_uploads_dir" ]; then
					var_backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_uploads_dir"
					var_backup_bucket_path=$(echo "$var_backup_bucket_path" | tr -s /)
					
					restore_remote_src_uploads="s3://$var_backup_bucket_path"
				elif [ ! -z "$var_setup_remote_bucket_path_uploads_file" ]; then
					setup_uploads_zip_file_name="uploads-$key.zip"
					setup_uploads_zip_file="$var_uploads_main_dir/$setup_uploads_zip_file_name"

					var_backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_uploads_file"
					var_backup_bucket_path=$(echo "$var_backup_bucket_path" | tr -s /)
					
					restore_remote_src_uploads="s3://$var_backup_bucket_path"
					restore_local_dest_uploads="/$setup_uploads_zip_file"
					restore_local_dest_uploads=$(echo "$restore_local_dest_uploads" | tr -s /)
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
			fi
		fi
		;;
	"setup:db")
		# Restore the database
    cd "$pod_full_dir"
		"$pod_script_env_file" up "$var_restore_service" "$var_db_service"
		
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
    
		restore_remote_src_db=""
		restore_local_dest_db=""

		sql_tables="select count(*) from information_schema.tables where table_schema = '$var_db_name'"
		sql_output="$("$pod_script_env_file" exec-nontty "$var_db_service" \
			mysql -u "$var_db_user" -p"$var_db_pass" -N -e "$sql_tables")" ||:
		tables=""

		if [ ! -z "$sql_output" ]; then
			tables="$(echo "$sql_output" | tail -n 1)"
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			tables=""
		fi

		if [ -z "$tables" ]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - wait for db to be ready${NC}"
			sleep 60
			sql_output="$("$pod_script_env_file" exec-nontty "$var_db_service" \
				mysql -u "$var_db_user" -p"$var_db_pass" -N -e "$sql_tables")" ||:

			if [ ! -z "$sql_output" ]; then
				tables="$(echo "$sql_output" | tail -n 1)"
			fi
		fi

		re='^[0-9]+$'

		if ! [[ $tables =~ $re ]] ; then
			msg="Could nor verify number of tables in database - output: $sql_output"
			echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
			exit 1
		fi

		if [ "$tables" != "0" ]; then
			msg="The database already has $tables tables, skipping database restore..."
			echo -e "${CYAN}$(date '+%F %X') - ${msg}${NC}"
		else
			if [ ! -z "$var_setup_local_db_file" ] \
			|| [ ! -z "$var_setup_remote_db_file" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_db_dir" ] \
			|| [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
				
				if [ ! -z "$var_setup_local_db_file" ]; then
					setup_db_file="$var_setup_local_db_file"
				elif [ ! -z "$var_setup_remote_db_file" ]; then
					setup_db_file_name="db-$key.zip"
					setup_db_file="$var_db_restore_dir/$setup_db_file_name"
				elif [ ! -z "$var_setup_remote_bucket_path_db_dir" ]; then
					setup_db_file="$var_db_restore_dir/$var_db_name.sql"

					var_backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_db_dir"
					var_backup_bucket_path=$(echo "$var_backup_bucket_path" | tr -s /)
					
					restore_remote_src_db="s3://$var_backup_bucket_path"
				elif [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
					setup_db_file_name="db-$key.zip"
					setup_db_file="$var_db_restore_dir/$setup_db_file_name"

					var_backup_bucket_path="$backup_bucket_prefix/$var_setup_remote_bucket_path_db_file"
					var_backup_bucket_path=$(echo "$var_backup_bucket_path" | tr -s /)
					
					restore_remote_src_db="s3://$var_backup_bucket_path"
					restore_local_dest_db="/$setup_db_file"
					restore_local_dest_db=$(echo "$restore_local_dest_db" | tr -s /)
				fi

				extension=${setup_db_file##*.}

				if [ "$extension" = "zip" ]; then
					setup_db_sql_file="$var_db_restore_dir/$var_db_name.sql"
				else
					setup_db_sql_file="$setup_db_file"
				fi

				echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
				"$pod_script_env_file" up "$var_restore_service"
				"$pod_script_env_file" exec-nontty "$var_restore_service" /bin/bash <<-SHELL
					set -eou pipefail

					rm -rf "/$var_db_restore_dir"
					mkdir -p "/$var_db_restore_dir"
				
					if [ ! -z "$var_setup_local_db_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore db from local file${NC}"
					elif [ ! -z "$var_setup_remote_db_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore db from remote file${NC}"
						curl -L -o "/$setup_db_file" -k "$var_setup_remote_db_file"
					elif [ ! -z "$var_setup_remote_bucket_path_db_dir" ]; then
						msg="$command - restore db from remote bucket dir"
						msg="\$msg [$restore_remote_src_db -> $var_db_restore_dir]"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

						if [ "$var_use_aws_s3" = 'true' ]; then
							msg="$command - $var_backup_service - aws_s3 - sync bucket db dir to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3 sync \
								--endpoint="$var_s3_endpoint" \
								"$restore_remote_src_db" "/$var_db_restore_dir"
						elif [ "$var_use_s3cmd" = 'true' ]; then
							msg="$command - $var_backup_service - s3cmd - sync bucket db dir to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							s3cmd sync "$restore_remote_src_db" "/$var_db_restore_dir"
						else
							msg="$command - $var_backup_service - not able to sync bucket db dir to local path"
							echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
							exit 1
						fi
					elif [ ! -z "$var_setup_remote_bucket_path_db_file" ]; then
						msg="$command - restore db from remote bucket"
						msg="\$msg [$restore_remote_src_db -> $restore_local_dest_db]"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

						if [ "$var_use_aws_s3" = 'true' ]; then
							msg="$command - $var_backup_service - aws_s3 - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3 cp \
								--endpoint="$var_s3_endpoint" \
								"$restore_remote_src_db" "$restore_local_dest_db"
						elif [ "$var_use_s3cmd" = 'true' ]; then
							msg="$command - $var_backup_service - s3cmd - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
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
						echo -e "${CYAN}$(date '+%F %X') - $command - db unzip${NC}"
						unzip "/$setup_db_file" -d "/$var_db_restore_dir"
					fi
				SHELL
				
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - main${NC}"
				"$pod_script_env_file" "setup:db:mysql" "$setup_db_sql_file"
			else
		    "$pod_script_env_file" "setup:db:new"
			fi
		fi
		;;
  "setup:db:mysql")
		setup_db_sql_file="${1:-}"

		if [ -z "$setup_db_sql_file" ]; then
			echo -e "${RED}[setup:db:mysql] setup_db_sql_file not specified${NC}"
			exit 1
		fi

		"$pod_script_env_file" exec-nontty "$var_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mysql -u "$var_db_user" -p"$var_db_pass" -e "CREATE DATABASE IF NOT EXISTS $var_db_name;"
			pv "/$setup_db_sql_file" | mysql -u "$var_db_user" -p"$var_db_pass" "$var_db_name"
		SHELL
		;;
  "backup")
		echo -e "${CYAN}$(date '+%F %X') - $command - started${NC}"

		cd "$pod_full_dir/"
		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_dir="$var_main_backup_base_dir/$main_backup_name"
		backup_bucket_prefix="$var_backup_bucket_name/$var_backup_bucket_path"
		backup_bucket_prefix="$(echo "$backup_bucket_prefix" | tr -s /)"
		var_backup_bucket_uploads_sync_dir_full="$var_backup_bucket_name/$var_backup_bucket_path/$var_backup_bucket_uploads_sync_dir"
		var_backup_bucket_uploads_sync_dir_full="$(echo "$var_backup_bucket_uploads_sync_dir_full" | tr -s /)"
		var_backup_bucket_db_sync_dir_full="$var_backup_bucket_name/$var_backup_bucket_path/$var_backup_bucket_db_sync_dir"
		var_backup_bucket_db_sync_dir_full="$(echo "$var_backup_bucket_db_sync_dir_full" | tr -s /)"		

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
		"$pod_script_env_file" "backup:db:mysql"
	
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
							"s3://$var_backup_bucket_uploads_sync_dir_full/"
					fi

					if [ ! -z "$var_backup_bucket_db_sync_dir" ]; then
						msg="$command - $var_backup_service - aws_s3 - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$var_s3_endpoint" \
							"/$var_db_backup_dir/" \
							"s3://$var_backup_bucket_db_sync_dir_full/"
					fi
				elif [ "$var_use_s3cmd" = 'true' ]; then
					msg="$command - $var_backup_service - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "/$var_main_backup_base_dir/" "s3://$backup_bucket_prefix"

					if [ ! -z "$var_backup_bucket_uploads_sync_dir" ]; then
						msg="$command - $var_backup_service - s3cmd - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$var_uploads_service_dir/" "s3://$var_backup_bucket_uploads_sync_dir_full/"
					fi

					if [ ! -z "$var_backup_bucket_db_sync_dir" ]; then
						msg="$command - $var_backup_service - s3cmd - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$var_db_backup_dir/" "s3://$var_backup_bucket_db_sync_dir_full/"
					fi
				else
					msg="$command - $var_backup_service - not able to sync local backup with bucket"
					echo -e "${YELLOW}\$(date '+%F %X') - \${msg}${NC}"
				fi
			fi

			if ! [[ $var_backup_delete_old_days =~ $re_number ]] ; then
				msg="The variable 'backup_delete_old_days' should be a number"
				msg="\$msg (value=$var_backup_delete_old_days)"
				echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
				exit 1
			fi

			find /$var_main_backup_base_dir/* -ctime +$var_backup_delete_old_days -delete;
			find /$var_main_backup_base_dir/* -maxdepth 0 -type d -ctime \
			  +$var_backup_delete_old_days -exec rm -rf {} \;
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;
	"backup:db:mysql")
		"$pod_script_env_file" exec-nontty "$var_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mysqldump -u "$var_db_user" -p"$var_db_pass" "$var_db_name" > "/$var_db_backup_dir/$var_db_name.sql"
		SHELL
    ;;
  *)
		echo -e "${RED}Invalid command: $command ${NC}"
		exit 1
    ;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f"|"setup"|"setup:uploads"|"setup:db"|"setup:db:mysql"|"backup"|"backup:db:mysql")
    echo -e "${CYAN}$(date '+%F %X') - $command - end${NC}"
    echo -e "${CYAN}$command - $start - $end${NC}"
    ;;
esac