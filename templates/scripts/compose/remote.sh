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

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -z "$dir" ] || [ "$dir" = "/" ]; then
    msg="This project must be in a directory structure of type [base_dir]/[this_repo]"
    msg="$msg with base_dir different than '' or '/'"
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
    echo -e "${CYAN}$(date '+%F %X') - $command - build...${NC}"
    $pod_layer_dir/run build

    if [[ "$command" = @("migrate"|"m") ]]; then
      echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
      $pod_layer_dir/run setup 
    elif [[ "$command" != @("fast-update"|"f") ]]; then
      echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
      $pod_layer_dir/run deploy 
    fi
    
    echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
    $pod_layer_dir/run run
    echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
    ;;
  "setup")
    cd $pod_layer_dir/
    sudo docker-compose rm -f --stop wordpress

    $pod_layer_dir/env/scripts/run before-setup
    
    tables="$(sudo docker-compose run --rm wordpress wp --allow-root db tables --all-tables | wc -l)"

    if [ "$tables" = "0" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
        sudo docker-compose run --rm wordpress \
            wp --allow-root core install \
            --url="$setup_url" \
            --title="$setup_title" \
            --admin_user="$setup_admin_user" \
            --admin_password="$setup_admin_password" \
            --admin_email="$setup_admin_email"

        if [ ! -z "$setup_local_seed_data" ]; then
            echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
            sudo docker-compose run --rm wordpress \
                wp --allow-root import ./"$setup_local_seed_data" --authors=create
        fi

        if [ ! -z "$setup_remote_seed_data" ]; then
            echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
            sudo docker-compose run --rm wordpress \
                curl -o ./tmp/tmp-seed-data.xml -k "$setup_remote_seed_data"
            sudo docker-compose run --rm wordpress \
                wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create
            sudo docker-compose run --rm wordpress \
                rm -f ./tmp/tmp-seed-data.xml
        fi
    fi

    echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
    $pod_layer_dir/run deploy 

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
  "build"|"exec"|"restart"|"logs")
    cd $pod_layer_dir/
    sudo docker-compose ${@}
    ;;
  "sh"|"bash")
    cd $pod_layer_dir/
    sudo docker-compose exec ${2} /bin/$command
    ;;
  "backup")
    cd $pod_layer_dir/
    file_name="wordpress_dbase-$(date '+%Y%m%d_%H%M%S')"
    sudo docker-compose exec mysql \
      sh -c "mysqldump -u '$db_user' -p'$db_pass' '$db_name' > '/tmp/main/$file_name.sql'"
    sudo docker-compose exec mysql \
      zip "/tmp/main/$file_name.zip" "/tmp/main/$file_name.sql"
    ;;
  *)
    echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
    exit 1
    ;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"