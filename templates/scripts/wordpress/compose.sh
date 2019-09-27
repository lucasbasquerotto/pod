#!/bin/bash
set -eou pipefail

repo_name="{{ params.repo_name }}"
setup_url='{{ params.setup_url }}' \
setup_title='{{ params.setup_title }}' \
setup_admin_user='{{ params.setup_admin_user }}' \
setup_admin_password='{{ params.setup_admin_password }}' \
setup_admin_email='{{ params.setup_admin_email }}'
setup_local_db_file='{{ params.setup_local_db_file }}'
setup_remote_db_file='{{ params.setup_remote_db_file }}'
setup_local_uploads_zip_file='{{ params.setup_local_uploads_zip_file }}'
setup_remote_uploads_zip_file='{{ params.setup_remote_uploads_zip_file }}'
setup_local_seed_data='{{ params.setup_local_seed_data }}'
setup_remote_seed_data='{{ params.setup_remote_seed_data }}'
s3_endpoint='{{ params.s3_endpoint }}'
use_aws_s3='{{ params.use_aws_s3 }}'
use_s3cmd='{{ params.use_s3cmd }}'
backup_bucket_name='{{ params.backup_bucket_name }}'
backup_bucket_path='{{ params.backup_bucket_path }}'
backup_delete_old_days='{{ params.backup_delete_old_days }}'
db_user='{{ params.db_user }}'
db_pass='{{ params.db_pass }}'
db_name='{{ params.db_name }}'

command="${1:-}"
commands="update (u), fast-update (f), prepare (p), deploy, run, stop"
commands="$commands, build, exec, restart, logs, sh, bash"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
layer_dir="$(dirname "$dir")"
base_dir="$(dirname "$layer_dir")"
re_number='^[0-9]+$'

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$dir" ] || [ "$dir" = "/" ]; then
	msg="This project must not be in the '/' directory"
	echo -e "${RED}${msg}${NC}"
	exit 1
fi

if [ -z "$command" ]; then
	echo -e "${RED}No command passed (valid commands: $commands)${NC}"
	exit 1
fi

pod_layer_dir="$dir"
	
start="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f")
		echo -e "${CYAN}$(date '+%F %X') - $command - prepare...${NC}"
		$pod_layer_dir/run prepare 
		echo -e "${CYAN}$(date '+%F %X') - $command - build...${NC}"
		$pod_layer_dir/run build

		if [[ "$command" = @("migrate"|"m") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - setup...${NC}"
			$pod_layer_dir/run setup 
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
			$pod_layer_dir/run deploy 
		fi
		
		echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
		$pod_layer_dir/run run
		echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
		;;
	"prepare"|"p")
		$pod_layer_dir/env/scripts/run prepare "$repo_name" ${@:2}
		;;
	"setup")
		cd $pod_layer_dir/
		sudo docker-compose rm -f --stop wordpress mysql

		$pod_layer_dir/env/scripts/run before-setup

		cd $pod_layer_dir/
		sudo docker-compose up -d mysql
		
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
			if [ ! -z "$setup_local_db_file" ] || [ ! -z "$setup_remote_db_file" ]; then
				main_restore_base_dir="tmp/main/backup"
				db_restore_dir="tmp/main/mysql/backup"
				uploads_restore_dir="tmp/main/wordpress/uploads"

				echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
				sudo docker-compose up -d toolbox
				sudo docker exec -i "$(sudo docker-compose ps -q toolbox)" /bin/bash <<-EOF
					set -eou pipefail

					rm -rf "/$db_restore_dir"
					mkdir -p "/$db_restore_dir"

					rm -rf "/$uploads_restore_dir"
					mkdir -p "/$uploads_restore_dir"
				EOF
				
				if [ ! -z "$setup_local_db_file" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - restore db from local file${NC}"
					setup_db_file="$setup_local_db_file"
				else
					echo -e "${CYAN}$(date '+%F %X') - $command - restore db from remote file${NC}"

					setup_db_file_name="wordpress-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
					setup_db_file="/$db_restore_dir/$setup_db_file_name.zip"

					sudo docker-compose exec toolbox \
						curl -L -o "$setup_db_file" -k "$setup_remote_db_file"
				fi

				file_name=${setup_db_file##*/}
				file_name=${file_name%.*}
				extension=${setup_db_file##*.}

				sudo docker-compose exec toolbox \
					rm -f "$db_restore_dir/$db_name.sql"

				if [ "$extension" = "zip" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - unzip db file${NC}"
					file_name=${setup_db_file##*/}
					file_name=${file_name%.*}
					sudo docker-compose exec toolbox \
						unzip "$setup_db_file" -d "$db_restore_dir"
					setup_db_file="$db_restore_dir/$db_name.sql"
				fi
				
				echo -e "${CYAN}$(date '+%F %X') - $command - db restore${NC}"
				sudo docker exec -i "$(sudo docker-compose ps -q mysql)" /bin/bash <<-EOF
					set -eou pipefail
					pv "$setup_db_file" | mysql -u "$db_user" -p"$db_pass" "$db_name"
				EOF
				
				if [ ! -z "$setup_local_uploads_zip_file" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from local dir${NC}"
					setup_uploads_zip_file="$setup_local_uploads_zip_file"
				elif [ ! -z "$setup_remote_uploads_zip_file" ]; then
					echo -e "${CYAN}$(date '+%F %X') - $command - restore uploads from remote dir${NC}"

					setup_uploads_zip_file_name="uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
					setup_uploads_zip_file="/$uploads_restore_dir/$setup_uploads_zip_file_name.zip"

					sudo docker-compose exec toolbox \
						curl -L -o "$setup_uploads_zip_file" -k "$setup_remote_uploads_zip_file"
				fi

				uploads_restore_specific_dir="/$uploads_restore_dir/uploads-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore${NC}"
				sudo docker exec -i $(sudo docker-compose ps -q toolbox) \
					unzip "$setup_uploads_zip_file" -d "/$uploads_restore_specific_dir"

				echo -e "${CYAN}$(date '+%F %X') - $command - uploads restore - main${NC}"
				sudo docker-compose run --rm wordpress \
					cp -r  "/$uploads_restore_specific_dir" "/var/www/html/web/app/uploads"

				echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
				$pod_layer_dir/run deploy 
			else
				echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
				sudo docker-compose run --rm wordpress \
					wp --allow-root core install \
					--url="$setup_url" \
					--title="$setup_title" \
					--admin_user="$setup_admin_user" \
					--admin_password="$setup_admin_password" \
					--admin_email="$setup_admin_email"

				echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
				$pod_layer_dir/run deploy 

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

		$pod_layer_dir/env/scripts/run after-setup
		;;
	"deploy")
		$pod_layer_dir/env/scripts/run before-deploy

		echo -e "${CYAN}$(date '+%F %X') - env - $command - upgrade${NC}"
		$pod_layer_dir/env/scripts/upgrade

		$pod_layer_dir/env/scripts/run after-deploy
		;;
	"run")
		$pod_layer_dir/env/scripts/run before-run
		details="${2:-}"
		cd $pod_layer_dir/
		sudo docker-compose up -d --remove-orphans $details
		$pod_layer_dir/env/scripts/run after-run
		;;
	"stop")
		$pod_layer_dir/env/scripts/run before-stop
		cd $pod_layer_dir/
		sudo docker-compose rm --stop -v --force
		$pod_layer_dir/env/scripts/run after-stop
		;;
	"stop-all")
		sudo docker stop $(sudo docker ps -q)
		;;
	"rm-all")
		sudo docker rm --force $(sudo docker ps -aq)
		;;
	"build"|"exec"|"restart"|"logs")
		cd $pod_layer_dir/
		sudo docker-compose ${@}
		;;
	"sh"|"bash")
		cd $pod_layer_dir/
		sudo docker-compose exec ${2} /bin/$command
		;;
	"backup")
		echo -e "${CYAN}$(date '+%F %X') - $command - started${NC}"

		cd $pod_layer_dir/
		main_backup_name="backup-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
		main_backup_base_dir="tmp/main/backup"
		db_backup_dir="tmp/main/mysql/backup"
		uploads_backup_dir="tmp/main/wordpress/uploads"
		main_backup_dir="$main_backup_base_dir/$main_backup_name"
		sql_file_name="$db_name.sql"
		backup_bucket_prefix="$backup_bucket_name/$backup_bucket_path/$main_backup_name/"
		backup_bucket_prefix=$(echo "$backup_bucket_prefix" | tr -s /)

		echo -e "${CYAN}$(date '+%F %X') - $command - start services needed${NC}"
		sudo docker-compose up -d toolbox wordpress mysql
	
		echo -e "${CYAN}$(date '+%F %X') - $command - create and clean directories${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q toolbox) /bin/bash <<-EOF
			set -eou pipefail

			rm -rf "/$db_backup_dir"
			mkdir -p "/$db_backup_dir"

			rm -rf "/$uploads_backup_dir"
			mkdir -p "/$uploads_backup_dir"
		EOF

		echo -e "${CYAN}$(date '+%F %X') - $command - db backup${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q mysql) /bin/bash <<-EOF
			set -eou pipefail
			mysqldump -u "$db_user" -p"$db_pass" "$db_name" > "/$db_backup_dir/$db_name.sql"
		EOF

		echo -e "${CYAN}$(date '+%F %X') - $command - uploads backup${NC}"
		sudo docker-compose exec wordpress \
			cp -r "/var/www/html/web/app/uploads" "/$uploads_backup_dir"
	
		echo -e "${CYAN}$(date '+%F %X') - $command - main backup${NC}"
		sudo docker exec -i $(sudo docker-compose ps -q toolbox) /bin/bash <<-EOF
			set -eou pipefail

			zip -j "/$db_backup_dir/db.zip" "/$db_backup_dir/$db_name.sql"
			cd '/$uploads_backup_dir'
			zip -r uploads.zip ./*

			mkdir -p "/$main_backup_dir"

			mv "/$db_backup_dir/db.zip" "/$main_backup_dir/db.zip"
			mv "/$uploads_backup_dir/uploads.zip" "/$main_backup_dir/uploads.zip"

			if [ ! -z "$backup_bucket_name" ]; then
				if [ "$use_aws_s3" = 'true' ]; then
					if aws s3 --endpoint="$s3_endpoint" ls "s3://$backup_bucket_name" 2>&1 | grep -q 'NoSuchBucket'; then
						aws s3api create-bucket \
							--endpoint="$s3_endpoint" \
							--bucket "$backup_bucket_name" 
					fi

					msg="$command - toolbox - aws_s3 - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					aws s3 sync \
						--endpoint="$s3_endpoint" \
						"/$main_backup_base_dir/" \
						"s3://$backup_bucket_prefix"
				elif [ "$use_s3cmd" = 'true' ]; then
					msg="$command - toolbox - s3cmd - sync local backup with bucket"
					echo -e "${CYAN}\$(date '+%F %X') - \${msg}${NC}"
					s3cmd sync "/$main_backup_base_dir/" "s3://$backup_bucket_prefix"
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
		EOF

		echo -e "${CYAN}$(date '+%F %X') - $command - generated backup file(s) at '/$main_backup_dir'${NC}"
		;;
	*)
		echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
		exit 1
		;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"