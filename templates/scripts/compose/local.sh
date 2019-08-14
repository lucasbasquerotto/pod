#!/bin/bash
set -eou pipefail

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

if [ -z "$base_dir" ] || [ "$base_dir" = "/" ]; then
    msg="This project must be in a directory structure of type [base_dir]/[layer_dir]/[this_repo]"
    msg="$msg with base_dir different than '' or '/'"
    echo -e "${RED}${msg}${NC}"
    exit 1
fi

if [ -z "$command" ]; then
    echo -e "${RED}No command passed (valid commands: $commands)${NC}"
    exit 1
fi

ctl_layer_dir="$base_dir/ctl"
pod_layer_dir="$dir"
repo_name="{{ params.repo_name }}"
    
start="$(date '+%F %X')"

if [ "$command" = "update" ] || [ "$command" = "u" ]; then
    echo -e "${CYAN}$(date '+%F %X') - update - prepare...${NC}"
    $pod_layer_dir/run prepare 
    echo -e "${CYAN}$(date '+%F %X') - update - build...${NC}"
    $pod_layer_dir/run build
    echo -e "${CYAN}$(date '+%F %X') - update - deploy...${NC}"
    $pod_layer_dir/run deploy
    echo -e "${CYAN}$(date '+%F %X') - update - run...${NC}"
    $pod_layer_dir/run run
    echo -e "${CYAN}$(date '+%F %X') - update - ended${NC}"
elif [ "$command" = "fast-update" ] || [ "$command" = "f" ]; then
    echo -e "${CYAN}$(date '+%F %X') - update - prepare...${NC}"
    $pod_layer_dir/run prepare 
    echo -e "${CYAN}$(date '+%F %X') - update - build...${NC}"
    $pod_layer_dir/run build
    echo -e "${CYAN}$(date '+%F %X') - update - run...${NC}"
    $pod_layer_dir/run run
    echo -e "${CYAN}$(date '+%F %X') - update - ended${NC}"
elif [ "$command" = "prepare" ] || [ "$command" = "p" ]; then
    start="$(date '+%F %X')"
    $pod_layer_dir/env/scripts/run before-prepare
    $ctl_layer_dir/run dev-cmd /root/r/w/$repo_name/dev ${@:2}
    $pod_layer_dir/env/scripts/run after-prepare
elif [ "$command" = "deploy" ]; then
    $pod_layer_dir/env/scripts/run deploy
elif [ "$command" = "run" ]; then
    $pod_layer_dir/env/scripts/run before-run
    details="${2:-}"
    cd $pod_layer_dir/
    sudo docker-compose up -d --remove-orphans $details
    $pod_layer_dir/env/scripts/run after-run
elif [ "$command" = "stop" ]; then
    $pod_layer_dir/env/scripts/run before-stop
    $ctl_layer_dir/run stop

    cd $pod_layer_dir/
    sudo docker-compose rm --stop -v --force
    $pod_layer_dir/env/scripts/run after-stop
elif [ "$command" = "build" ] || [ "$command" = "exec" ] \
     || [ "$command" = "restart" ]|| [ "$command" = "logs" ]; then
    cd $pod_layer_dir/
    sudo docker-compose ${@}
elif [ "$command" = "sh" ] || [ "$command" = "bash" ]; then
    cd $pod_layer_dir/
    sudo docker-compose exec ${2} /bin/$command
else
    echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
    exit 1
fi

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"