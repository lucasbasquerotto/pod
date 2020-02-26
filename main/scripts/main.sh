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

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_names ) task_names="${OPTARG:-}";;

		task_name ) task_name="${OPTARG:-}";; 
		task_name_verify ) task_name_verify="${OPTARG:-}";; 
		task_name_remote ) task_name_remote="${OPTARG:-}";; 
		task_name_local ) task_name_local="${OPTARG:-}";; 
		task_name_new ) task_name_new="${OPTARG:-}";; 

		setup_service ) setup_service="${OPTARG:-}";;
		setup_dest_dir ) setup_dest_dir="${OPTARG:-}";;
		setup_run_new_task ) setup_run_new_task="${OPTARG:-}";;

		backup_service ) backup_service="${OPTARG:-}";;
		backup_base_dir ) backup_base_dir="${OPTARG:-}";;
		backup_delete_old_days ) backup_delete_old_days="${OPTARG:-}";;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

function run_tasks {
  task_names="${1:-}" 
  task_parameter_name="${2:-}"

  if [ ! -z "${task_names:-}" ]; then
    IFS=',' read -r -a tmp <<< "${task_names}"
    arr=("${tmp[@]}")

    for task_name in "${arr[@]}"; do
      "$pod_script_env_file" "$task_name" "${args[@]}" \
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
			echo -e "${CYAN}$(date '+%F %T') - $command - upgrade...${NC}"
			"$pod_script_env_file" upgrade "${args[@]}" 
		fi
		
		echo -e "${CYAN}$(date '+%F %T') - $command - run...${NC}"
		"$pod_script_env_file" up
		echo -e "${CYAN}$(date '+%F %T') - $command - ended${NC}"
		;;
	"setup"|"fast-setup")    
		run_tasks "${task_names:-}" "task_name"

    if [ "$command" = "setup" ]; then
      "$pod_script_env_file" upgrade "${args[@]}" 
    fi
		;;
	"setup:default")
		echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - start needed services${NC}"
		"$pod_script_env_file" up "$setup_service"

		msg="verify if the setup should be done"
		echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - $msg ${NC}"
		skip="$("$pod_script_env_file" "${task_name_verify}" "${args[@]}")"
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$command ($task_name): $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($task_name) - skipping..."
		elif [ "${setup_run_new_task:-}" = "true" ]; then
			"$pod_script_env_file" "${task_name_new}"
		else 
			echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - restore - remote${NC}"
			setup_restored_file="$("$pod_script_env_file" \
				"${task_name_remote}" "${args[@]}")"

			>&2 echo "setup_restored_file=$setup_restored_file"

			if [ -z "${setup_restored_file:-}" ]; then
				error "$command ($task_name): unknown file/directory to restore"
			fi
			
			if [ ! -z "${task_name_local:-}" ]; then
				echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - restore - local${NC}"
				"$pod_script_env_file" "${task_name_local}" \
					"${args[@]}" --setup_restored_path="$setup_restored_file"
			fi
		fi
		;;
	"setup:verify")
		msg="verify if the directory ${setup_dest_dir:-} is empty"
		>&2 echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - $msg ${NC}"

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
	"backup")	
		run_tasks "${task_names:-}" "task_name"
		;;  
	"backup:default")
		echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - started${NC}"

    re_number='^[0-9]+$'

		if ! [[ $backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="\$msg (value=$backup_delete_old_days)"
			error "$msg"
		fi

		if [ -z "${task_name_verify:-}" ]; then
			skip="false"
		else
			msg="verify if the backup should be done"
			echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - $msg ${NC}"
			skip="$("$pod_script_env_file" "${task_name_verify}" "${args[@]}")"
		fi
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$command ($task_name): $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($task_name) - skipping..."
		else 			
			if [ ! -z "${task_name_local:-}" ]; then
				echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - backup - local${NC}"
				"$pod_script_env_file" "${task_name_local}" "${args[@]}"
			fi
			
			if [ ! -z "${task_name_remote:-}" ]; then
				echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - backup - remote${NC}"
				"$pod_script_env_file" "${task_name_remote}" "${args[@]}"
			fi

			echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - start needed services${NC}"
			"$pod_script_env_file" up "$backup_service"

			echo -e "${CYAN}$(date '+%F %T') - $command ($task_name) - clear old files${NC}"
			"$pod_script_env_file" exec-nontty "$backup_service" /bin/bash <<-SHELL
				set -eou pipefail			

				find /$backup_base_dir/* -ctime +$backup_delete_old_days -delete;
				find /$backup_base_dir/* -maxdepth 0 -type d -ctime \
					+$backup_delete_old_days -exec rm -rf {} \;
			SHELL
		fi
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