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
setup_local_seed_data='{{ params.setup_local_seed_data }}'
setup_remote_seed_data='{{ params.setup_remote_seed_data }}'
db_user='{{ params.db_user }}'
db_pass='{{ params.db_pass }}'
db_name='{{ params.db_name }}'

command="${1:-}"
commands="update (u), fast-update (f), prepare (p), deploy, run, stop"
commands="$commands, build, exec, restart, logs, sh, bash"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
layer_dir="$(dirname "$dir")"
base_dir="$(dirname "$layer_dir")"

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
		sudo docker-compose rm -f --stop wordpress

		$pod_layer_dir/env/scripts/run before-setup

		cd $pod_layer_dir/
		sudo docker-compose up -d mysql
		
		sql_tables="select count(*) from information_schema.tables where table_schema = '$db_name'"
		tables="$(sudo docker-compose exec -T mysql \
			mysql -u "$db_user" -p"$db_pass" -N -e "$sql_tables")" ||:

		if [ -z "$tables" ]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - wait for db to be ready${NC}"
			sleep 60
			tables="$(sudo docker-compose exec -T mysql \
				mysql -u "$db_user" -p"$db_pass" -N -e "$sql_tables")"
		fi

		if [ "$tables" = "0" ]; then
			if [ ! -z "$setup_local_db_file" ] || [ ! -z "$setup_remote_db_file" ]; then
				main_restore_base_dir="tmp/main/backup"
				db_restore_dir="tmp/main/mysql/backup"
				uploads_restore_dir="tmp/main/wordpress/uploads"

				echo -e "${CYAN}$(date '+%F %X') - $command - create and clean the directories${NC}"
				sudo docker-compose up -d toolbox
				sudo docker exec -i $(sudo docker-compose ps -q toolbox) /bin/bash <<-EOF
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

					setup_db_file_name="wordpress_dbase-$(date '+%Y%m%d_%H%M%S')-$(date '+%s')"
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
				sudo docker exec -i $(sudo docker-compose ps -q mysql) /bin/bash <<-EOF
					set -eou pipefail
					pv "$setup_db_file" | mysql -u "$db_user" -p"$db_pass" "$db_name"
				EOF

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

			rm -rf "/$main_backup_dir"
			mkdir -p "/$main_backup_dir"

			mv "/$db_backup_dir/db.zip" "/$main_backup_dir/db.zip"
			mv "/$uploads_backup_dir/uploads.zip" "/$main_backup_dir/uploads.zip"

			cd "/$main_backup_dir"
			zip -r "$main_backup_name.zip" ./*

			mv "$main_backup_name.zip" "/$main_backup_base_dir/$main_backup_name.zip"
			cd "/$main_backup_base_dir"
			rm -rf "/$main_backup_dir"
		EOF

		path="[data_dir]/$main_backup_base_dir/$main_backup_name.zip"
		echo -e "${CYAN}$(date '+%F %X') - $command - generated file at '$path'${NC}"
		;;
	*)
		echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
		exit 1
		;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"