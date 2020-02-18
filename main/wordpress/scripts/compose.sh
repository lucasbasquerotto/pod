#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

scripts_full_dir="${pod_layer_dir}/${scripts_dir}"

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

commands="migrate (m), update (u), fast-update (f), prepare (p), setup, deploy"
commands="$commands, up, run, stop, rm, build, exec, restart, logs, ps, sh, bash, backup"
re_number='^[0-9]+$'

if [ -z "$command" ]; then
	echo -e "${RED}No command passed (valid commands: $commands)${NC}"
	exit 1
fi

shift;
	
start="$(date '+%F %X')"

case "$command" in
	"migrate"|"m"|"update"|"u"|"fast-update"|"f")
		echo -e "${CYAN}$(date '+%F %X') - $command - prepare...${NC}"
		"$pod_script_root_run_file_full" "$pod_vars_dir" prepare 
		echo -e "${CYAN}$(date '+%F %X') - $command - build...${NC}"
		"$pod_script_root_run_file_full" "$pod_vars_dir" build

		if [[ "$command" = @("migrate"|"m") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - setup...${NC}"
			"$pod_script_root_run_file_full" "$pod_vars_dir" setup 
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
			"$pod_script_root_run_file_full" "$pod_vars_dir" deploy 
		fi
		
		echo -e "${CYAN}$(date '+%F %X') - $command - run...${NC}"
		"$pod_script_root_run_file_full" "$pod_vars_dir" up
		echo -e "${CYAN}$(date '+%F %X') - $command - ended${NC}"
		;;
	"prepare"|"p")
		"$scripts_full_dir/$script_env_file" prepare "$env_local_repo" "${@:2}"
		;;
	"backup")
		"$pod_script_env_file_full" backup
		;;
	"setup")
		"$pod_script_env_file_full" setup
		;;
	"deploy")
		"$pod_script_env_file_full" before-deploy

		if [ ! -z "$script_upgrade_file" ]; then
			echo -e "${CYAN}$(date '+%F %X') - env - $command - upgrade${NC}"
			"$pod_layer_dir/$scripts_dir/$script_upgrade_file"
		else
			echo -e "${CYAN}$(date '+%F %X') - env - $command - no upgrade defined${NC}"
		fi

		"$pod_script_env_file_full" after-deploy
		;;
	"up")
		"$pod_script_env_file_full" before-up
		cd "$pod_full_dir/"
		sudo docker-compose up -d --remove-orphans $@
		"$pod_script_env_file_full" after-up
		;;
	"stop")
		if [ $# -eq 0 ]; then
			"$pod_script_env_file_full" before-stop
		fi
		
		cd "$pod_full_dir/"
		sudo docker-compose stop $@
		
		if [ $# -eq 0 ]; then
			"$pod_script_env_file_full" after-stop
		fi
		;;
	"rm")
		if [ $# -eq 0 ]; then
			"$pod_script_env_file_full" before-rm
		fi

		cd "$pod_full_dir/"
		sudo docker-compose rm --stop -v --force $@

		if [ $# -eq 0 ]; then
			"$pod_script_env_file_full" after-rm
		fi
		;;
	"build"|"run"|"exec"|"restart"|"logs"|"ps")
		cd "$pod_full_dir/"
		sudo docker-compose "$command" ${@}
		;;
	"sh"|"bash")
		cd "$pod_full_dir/"
		sudo docker-compose exec "${1}" /bin/"$command"
		;;
	*)
		echo -e "${RED}Invalid command: $command (valid commands: $commands)${NC}"
		exit 1
		;;
esac

end="$(date '+%F %X')"
echo -e "${CYAN}$command - $start - $end${NC}"