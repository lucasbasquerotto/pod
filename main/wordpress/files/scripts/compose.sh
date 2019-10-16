#!/bin/bash
set -eou pipefail

. "${DIR}/vars.sh"

scripts_full_dir="${DIR}/${scripts_dir}"
pod_layer_dir="$DIR"
layer_dir="$(dirname "$DIR")"
base_dir="$(dirname "$layer_dir")"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$DIR" ] || [ "$DIR" = "/" ]; then
	msg="This project must not be in the '/' directory"
	echo -e "${RED}${msg}${NC}"
	exit 1
fi

command="${1:-}"
commands="update (u), fast-update (f), prepare (p), deploy, run, stop"
commands="$commands, build, exec, restart, logs, sh, bash"
re_number='^[0-9]+$'

if [ -z "$command" ]; then
	echo -e "${RED}No command passed (valid commands: $commands)${NC}"
	exit 1
fi
	
start="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f")
		echo -e "${CYAN}$(date '+%F %X') - $command - prepare...${NC}"
		"$pod_layer_dir/run" prepare 
		echo -e "${CYAN}$(date '+%F %X') - $command - build...${NC}"
		"$pod_layer_dir/run" build

		if [[ "$command" = @("migrate"|"m") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - setup...${NC}"
			"$pod_layer_dir/run" setup 
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
			"$pod_layer_dir/run" deploy 
		fi
		
		echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
		"$pod_layer_dir/run" run
		echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
		;;
	"prepare"|"p")
		"$scripts_full_dir/$script_env_file" prepare "$repo_name" ${@:2}
		;;
	"setup")
		cd "$pod_layer_dir/"
		sudo docker-compose rm -f --stop wordpress mysql

		"$pod_layer_dir/$scripts_dir/$script_env_file" before-setup

		"$pod_layer_dir/run" main-setup

		"$pod_layer_dir/$scripts_dir/$script_env_file" after-setup
		;;
	"main-setup")
		cd "$pod_layer_dir/"
		sudo docker-compose up -d toolbox mysql
		
		main_restore_base_dir="tmp/main/restore"
		db_restore_dir="tmp/main/mysql/backup"
		uploads_restore_dir="tmp/main/wordpress/uploads"
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		wp_uploads_toolbox_dir="tmp/data/wordpress/uploads"
		key="$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"

		setup_uploads_zip_file=""
		restore_remote_src_uploads=""
		restore_local_dest_uploads=""

		restore_remote_src_db=""
		restore_local_dest_db=""

		# Restore uploaded files

		dir_ls=$(sudo docker exec -i "$(sudo docker-compose ps -q toolbox)" find /${wp_uploads_toolbox_dir}/ -type f | wc -l)

		if [ -z "$dir_ls" ]; then
			dir_ls="0"
		fi

		if [[ $dir_ls -eq 0 ]]; then 
			if [ ! -z "$setup_local_uploads_zip_file" ] \
			|| [ ! -z "$setup_remote_uploads_zip_file" ] \
			|| [ ! -z "$setup_remote_bucket_path_uploads_file" ]; then

				if [ ! -z "$setup_local_uploads_zip_file" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
					setup_uploads_zip_file="$setup_local_uploads_zip_file"
				elif [ ! -z "$setup_remote_uploads_zip_file" ]; then
					setup_uploads_zip_file_name="uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s').zip"
					setup_uploads_zip_file="/$uploads_restore_dir/$setup_uploads_zip_file_name"
				elif [ ! -z "$setup_remote_bucket_path_uploads_dir" ]; then
					backup_bucket_path="$backup_bucket_prefix/$setup_remote_bucket_path_uploads_dir"
					backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
					
					restore_remote_src_uploads="s3://$backup_bucket_path"
				elif [ ! -z "$setup_remote_bucket_path_uploads_file" ]; then
					setup_uploads_zip_file_name="uploads-$key.zip"
					setup_uploads_zip_file="$uploads_restore_dir/$setup_uploads_zip_file_name"

					backup_bucket_path="$backup_bucket_prefix/$setup_remote_bucket_path_uploads_file"
					backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
					
					restore_remote_src_uploads="s3://$backup_bucket_path"
					restore_local_dest_uploads="/$setup_uploads_zip_file"
					restore_local_dest_uploads=$(echo "$restore_local_dest_uploads" | tr -s /)
				fi

				uploads_restore_specific_dir="$uploads_restore_dir/uploads-$key"

				echo -e "${CYAN}$(date '+%F %X') - $command - toolbox - restore${NC}"
				sudo docker-compose up -d toolbox
				sudo docker exec -i "$(sudo docker-compose ps -q toolbox)" /bin/bash <<-SHELL
					set -eou pipefail

					rm -rf "/$uploads_restore_dir"
					mkdir -p "/$uploads_restore_dir"
				
					if [ ! -z "$setup_local_uploads_zip_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
					elif [ ! -z "$setup_remote_uploads_zip_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from remote dir${NC}"
						curl -L -o "$setup_uploads_zip_file" -k "$setup_remote_uploads_zip_file"
					elif [ ! -z "$setup_remote_bucket_path_uploads_file" ]; then
						msg="$command - restore uploads zip file from remote bucket"
						msg="\$msg [$restore_remote_src_uploads -> $restore_local_dest_uploads]"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					
						if [ "$use_aws_s3" = 'true' ]; then
							msg="$command - toolbox - aws_s3 - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3 cp \
								--endpoint="$s3_endpoint" \
								"$restore_remote_src_uploads" "$restore_local_dest_uploads"
						elif [ "$use_s3cmd" = 'true' ]; then
							msg="$command - toolbox - s3cmd - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							s3cmd cp "$restore_remote_src_uploads" "$restore_local_dest_uploads"
						else
							msg="$command - toolbox - not able to copy bucket file to local path"
							echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
							exit 1
						fi
					fi

					if [ ! -z "$setup_remote_bucket_path_uploads_dir" ]; then
						msg="$command - restore uploads from remote bucket directly to uploads directory"
						msg="\$msg [$restore_remote_src_uploads -> /$wp_uploads_toolbox_dir]"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					
						if [ "$use_aws_s3" = 'true' ]; then
							msg="$command - toolbox - aws_s3 - sync bucket dir to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3 sync \
								--endpoint="$s3_endpoint" \
								"$restore_remote_src_uploads" "/$wp_uploads_toolbox_dir"
						elif [ "$use_s3cmd" = 'true' ]; then
							msg="$command - toolbox - s3cmd - sync bucket dir to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							s3cmd sync "$restore_remote_src_uploads" "/$wp_uploads_toolbox_dir"
						else
							msg="$command - toolbox - not able to sync bucket dir to local path"
							echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
							exit 1
						fi
					else
						echo -e "${CYAN}$(date '+%F %X') - $command - uploads unzip${NC}"
						unzip "/$setup_uploads_zip_file" -d "/$uploads_restore_specific_dir"

						echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - main${NC}"
						cp -r  "/$uploads_restore_specific_dir/uploads"/. "/$wp_uploads_toolbox_dir/"
					fi
				SHELL
			fi
		fi

		# Restore database
		
		sql_tables="select count(*) from information_schema.tables where table_schema = '$db_name'"
		tables="$(sudo docker-compose exec -T mysql \
			mysql -u "$db_user" -p"$db_pass" -N -e "$sql_tables")" ||:

		if [ ! -z "$tables" ]; then
			tables="$(echo "$tables" | tail -n 1)"
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			tables=""
		fi

		if [ -z "$tables" ]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - wait for db to be ready${NC}"
			sleep 60
			tables="$(sudo docker-compose exec -T mysql \
				mysql -u "$db_user" -p"$db_pass" -N -e "$sql_tables")"

			if [ ! -z "$tables" ]; then
				tables="$(echo "$tables" | tail -n 1)"
			fi
		fi

		re='^[0-9]+$'

		if ! [[ $tables =~ $re ]] ; then
			msg="Could nor verify number of tables in database - $tables"
			echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
			exit 1
		fi

		if [ "$tables" = "0" ]; then
			if [ ! -z "$setup_local_db_file" ] \
			|| [ ! -z "$setup_remote_db_file" ] \
			|| [ ! -z "$setup_remote_bucket_path_db_file" ]; then
				
				if [ ! -z "$setup_local_db_file" ]; then
					setup_db_file="$setup_local_db_file"
				elif [ ! -z "$setup_remote_db_file" ]; then
					setup_db_file_name="db-$key.zip"
					setup_db_file="$db_restore_dir/$setup_db_file_name"
				elif [ ! -z "$setup_remote_bucket_path_db_file" ]; then
					setup_db_file_name="db-$key.zip"
					setup_db_file="$db_restore_dir/$setup_db_file_name"

					backup_bucket_path="$backup_bucket_prefix/$setup_remote_bucket_path_db_file"
					backup_bucket_path=$(echo "$backup_bucket_path" | tr -s /)
					
					restore_remote_src_db="s3://$backup_bucket_path"
					restore_local_dest_db="/$setup_db_file"
					restore_local_dest_db=$(echo "$restore_local_dest_db" | tr -s /)
				fi

				extension=${setup_db_file##*.}

				if [ "$extension" = "zip" ]; then
					file_name=${setup_db_file##*/}
					file_name=${file_name%.*}
					setup_db_sql_file="$db_restore_dir/$db_name.sql"
				else
					setup_db_sql_file="$setup_db_file"
				fi

				echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
				sudo docker-compose up -d toolbox
				sudo docker exec -i "$(sudo docker-compose ps -q toolbox)" /bin/bash <<-SHELL
					set -eou pipefail

					rm -rf "/$db_restore_dir"
					mkdir -p "/$db_restore_dir"
				
					if [ ! -z "$setup_local_db_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore db from local file${NC}"
					elif [ ! -z "$setup_remote_db_file" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - restore db from remote file${NC}"
						curl -L -o "/$setup_db_file" -k "$setup_remote_db_file"
					elif [ ! -z "$setup_remote_bucket_path_db_file" ]; then
						msg="$command - restore db from remote bucket"
						msg="\$msg [$restore_remote_src_db -> $restore_local_dest_db]"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"

						if [ "$use_aws_s3" = 'true' ]; then
							msg="$command - toolbox - aws_s3 - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3 cp \
								--endpoint="$s3_endpoint" \
								"$restore_remote_src_db" "$restore_local_dest_db"
						elif [ "$use_s3cmd" = 'true' ]; then
							msg="$command - toolbox - s3cmd - copy bucket file to local path"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							s3cmd cp "$restore_remote_src_db" "$restore_local_dest_db"
						else
							msg="$command - toolbox - not able to copy bucket file to local path"
							echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
							exit 1
						fi
					else
						msg="$command - db file to restore not specified"
						echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
						exit 1
					fi

					rm -f "/$db_restore_dir/$db_name.sql"

					if [ "$extension" = "zip" ]; then
						echo -e "${CYAN}$(date '+%F %X') - $command - db unzip${NC}"
						unzip "/$setup_db_file" -d "/$db_restore_dir"
					fi
				SHELL
				
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore - main${NC}"
				sudo docker exec -i "$(sudo docker-compose ps -q mysql)" /bin/bash <<-SHELL
					set -eou pipefail
					pv "$setup_db_sql_file" | mysql -u "$db_user" -p"$db_pass" "$db_name"
				SHELL

				echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
				$pod_layer_dir/run deploy 
			else
				# Deploy a brand-new Wordpress site (with possibly seeded data)
				echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
				sudo docker-compose run --rm wordpress \
					wp --allow-root core install \
					--url="$setup_url" \
					--title="$setup_title" \
					--admin_user="$setup_admin_user" \
					--admin_password="$setup_admin_password" \
					--admin_email="$setup_admin_email"

				echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
				"$pod_layer_dir/run" deploy 

				if [ ! -z "$setup_local_seed_data" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
					sudo docker-compose run --rm wordpress \
						wp --allow-root import ./"$setup_local_seed_data" --authors=create
				fi

				if [ ! -z "$setup_remote_seed_data" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - import remote seed data${NC}"
					sudo docker-compose run --rm wordpress sh -c \
						"curl -L -o ./tmp/tmp-seed-data.xml -k '$setup_remote_seed_data' \
						&& wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
						&& rm -f ./tmp/tmp-seed-data.xml"
				fi
			fi
		fi
		;;
	"deploy")
		"$pod_layer_dir/$scripts_dir/$script_env_file" before-deploy

		echo -e "${CYAN}$(date '+%F %X') - env - $command - upgrade${NC}"
		"$pod_layer_dir/$scripts_dir/$script_upgrade_file"

		"$pod_layer_dir/$scripts_dir/$script_env_file" after-deploy
		;;
	"run")
		"$pod_layer_dir/$scripts_dir/$script_env_file" before-run
		details="${2:-}"
		cd "$pod_layer_dir/"
		sudo docker-compose up -d --remove-orphans $details
		"$pod_layer_dir/$scripts_dir/$script_env_file" after-run
		;;
	"stop")
		"$pod_layer_dir/$scripts_dir/$script_env_file" before-stop
		cd "$pod_layer_dir/"
		sudo docker-compose rm --stop -v --force
		"$pod_layer_dir/$scripts_dir/$script_env_file" after-stop
		;;
	"stop-all")
		sudo docker stop $(sudo docker ps -q)
		;;
	"rm-all")
		sudo docker rm --force $(sudo docker ps -aq)
		;;
	"build"|"exec"|"restart"|"logs")
		cd "$pod_layer_dir/"
		sudo docker-compose ${@}
		;;
	"sh"|"bash")
		cd "$pod_layer_dir/"
		sudo docker-compose exec ${2} /bin/$command
		;;
	"backup")
		echo -e "${CYAN}$(date '+%F %X') - $command - started${NC}"

		cd "$pod_layer_dir/"
		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_base_dir="tmp/main/backup"
		db_backup_dir="tmp/main/mysql/backup"
		uploads_toolbox_dir="tmp/wordpress/uploads"
		uploads_backup_dir="tmp/main/wordpress/uploads"
		main_backup_dir="$main_backup_base_dir/$main_backup_name"
		sql_file_name="$db_name.sql"
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path"
		backup_bucket_prefix="$(echo "$backup_bucket_prefix" | tr -s /)"
		backup_bucket_uploads_sync_dir_full="$backup_bucket_name/$backup_bucket_path/$backup_bucket_uploads_sync_dir"
		backup_bucket_uploads_sync_dir_full="$(echo "$backup_bucket_uploads_sync_dir_full" | tr -s /)"
		backup_bucket_db_sync_dir_full="$backup_bucket_name/$backup_bucket_path/$backup_bucket_db_sync_dir"
		backup_bucket_db_sync_dir_full="$(echo "$backup_bucket_db_sync_dir_full" | tr -s /)"		

		echo -e "${CYAN}$(date '+%F %X') - $command - start services needed${NC}"
		sudo docker-compose up -d toolbox wordpress mysql
	
		echo -e "${CYAN}$(date '+%F %X') - $command - create and clean directories${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q toolbox) /bin/bash <<-SHELL
			set -eou pipefail

			rm -rf "/$db_backup_dir"
			mkdir -p "/$db_backup_dir"

			rm -rf "/$uploads_backup_dir"
			mkdir -p "/$uploads_backup_dir"
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - db backup${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q mysql) /bin/bash <<-SHELL
			set -eou pipefail
			mysqldump -u "$db_user" -p"$db_pass" "$db_name" > "/$db_backup_dir/$db_name.sql"
		SHELL
	
		echo -e "${CYAN}$(date '+%F %X') - $command - main backup${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q toolbox) /bin/bash <<-SHELL
			set -eou pipefail

			mkdir -p "/$main_backup_dir"

			if [ -z "$backup_bucket_uploads_sync_dir" ]; then
				echo -e "${CYAN}$(date '+%F %X') - $command - uploads backup${NC}"
				cp -r "/$uploads_toolbox_dir" "/$uploads_backup_dir"
				cd '/$uploads_backup_dir'
				zip -r uploads.zip ./*
				mv "/$uploads_backup_dir/uploads.zip" "/$main_backup_dir/uploads.zip"
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
							msg="$command - toolbox - aws_s3 - create bucket $backup_bucket_name"
							echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
							aws s3api create-bucket \
								--endpoint="$s3_endpoint" \
								--bucket "$backup_bucket_name" 
						fi
					fi

					msg="$command - toolbox - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"/$main_backup_base_dir/" \
						"s3://$backup_bucket_prefix"

					if [ !-z "$backup_bucket_uploads_sync_dir" ]; then
						msg="$command - toolbox - aws_s3 - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$uploads_toolbox_dir/" \
							"s3://$backup_bucket_uploads_sync_dir_full/"
					fi

					if [ !-z "$backup_bucket_db_sync_dir" ]; then
						msg="$command - toolbox - aws_s3 - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						aws s3 sync \
							--endpoint="$s3_endpoint" \
							"/$db_backup_dir/" \
							"s3://$backup_bucket_db_sync_dir_full/"
					fi
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - toolbox - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "/$main_backup_base_dir/" "s3://$backup_bucket_prefix"

					if [ !-z "$backup_bucket_uploads_sync_dir" ]; then
						msg="$command - toolbox - s3cmd - sync local uploads dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$uploads_toolbox_dir/" "s3://$backup_bucket_uploads_sync_dir_full/"
					fi

					if [ !-z "$backup_bucket_db_sync_dir" ]; then
						msg="$command - toolbox - s3cmd - sync local db dir with bucket"
						echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
						s3cmd sync "/$db_backup_dir/" "s3://$backup_bucket_db_sync_dir_full/"
					fi
				else
					msg="$command - toolbox - not able to sync local backup with bucket"
					echo -e "${YELLOW}\$(date '+%F %X') - \${msg}${NC}"
				fi
			fi

			if ! [[ $backup_delete_old_days =~ $re_number ]] ; then
				msg="The variable 'backup_delete_old_days' should be a number"
				msg="\$msg (value=$backup_delete_old_days)"
				echo -e "${RED}\$(date '+%F %X') - \${msg}${NC}"
				exit 1
			fi

			find /$main_backup_base_dir/* -ctime +$backup_delete_old_days -delete;
			find /$main_backup_base_dir/* -maxdepth 0 -type d -ctime +$backup_delete_old_days -exec rm -rf {} \;
		SHELL

		echo -e "${CYAN}$(date '+%F %X') - $command - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;
	*)
		echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
		exit 1
		;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"