#!/bin/bash
set -eou pipefail

command="${1:-}"
commands="update, ansible, run, build, exec, restart, logs, stop"
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

ctl_layer_dir="$base_dir/ansible-manager"
pod_layer_dir="$dir"
repo_name="{{ params.repo_name }}"

if [ "$command" = "update" ] || [ "$command" = "u" ]; then    
    echo -e "${CYAN}update - prepare...${NC}"
    $pod_layer_dir/run prepare 
    echo -e "${CYAN}update - build...${NC}"
    $pod_layer_dir/run build
    echo -e "${CYAN}update - run...${NC}"
    $pod_layer_dir/run run
    echo -e "${CYAN}update - ended${NC}"
elif [ "$command" = "prepare" ] || [ "$command" = "p" ]; then
    $ctl_layer_dir/run dev-cmd /root/r/w/$repo_name/dev
elif [ "$command" = "run" ]; then
    details="${2:-}"
    cd $pod_layer_dir/
    sudo docker-compose up -d --remove-orphans $details
elif [ "$command" = "build" ] || [ "$command" = "exec" ] || [ "$command" = "logs" ] || [ "$command" = "restart" ]; then
    cd $pod_layer_dir/
    sudo docker-compose ${@}
elif [ "$command" = "stop" ]; then
    $ctl_layer_dir/run stop

    cd $pod_layer_dir/
    sudo docker-compose rm --stop -v
else
    echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
    exit 1
fi