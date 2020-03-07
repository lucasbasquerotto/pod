#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

GRAY="\033[0;90m"
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	msg="$(date '+%F %T') - ${1:-}"
	>&2 echo -e "${GRAY}${msg}${NC}"
}

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
		toolbox_service ) toolbox_service="${OPTARG:-}";;

		setup_run_new_task ) setup_run_new_task="${OPTARG:-}";;    
		setup_dest_dir_to_verify ) setup_dest_dir_to_verify="${OPTARG:-}";;
		
		backup_local_dir ) backup_local_dir="${OPTARG:-}";;
		backup_delete_old_days ) backup_delete_old_days="${OPTARG:-}";;
		??* ) ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

function run_tasks {
  run_task_names="${1:-}" 

  if [ -n "${run_task_names:-}" ]; then
    IFS=',' read -r -a tmp <<< "${run_task_names}"
    arr=("${tmp[@]}")

    for task_name in "${arr[@]}"; do
      "$pod_script_env_file" "$task_name" "${args[@]}" \
        --task_name="$task_name"
    done
  fi
}

case "$command" in
	"migrate"|"update"|"fast-update")
		info "$command - prepare..."
		"$pod_script_env_file" prepare
		info "$command - build..."
		"$pod_script_env_file" build

		if [[ "$command" = @("migrate"|"m") ]]; then
			info "$command - setup..."
			"$pod_script_env_file" setup "${args[@]}"
		elif [[ "$command" != @("fast-update"|"f") ]]; then
			info "$command - upgrade..."
			"$pod_script_env_file" upgrade "${args[@]}" 
		fi
		
		info "$command - run..."
		"$pod_script_env_file" up
		info "$command - ended"
		;;
	"setup"|"fast-setup")    
		run_tasks "${task_names:-}"

    if [ "$command" = "setup" ]; then
      "$pod_script_env_file" upgrade "${args[@]}" 
    fi
		;;
	"setup:default")
		info "$command ($task_name) - start needed services"
		"$pod_script_env_file" up "$toolbox_service"

		msg="verify if the setup should be done"
		info "$command ($task_name) - $msg "
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
			if [ -n "${task_name_remote:-}" ]; then
				info "$command ($task_name) - restore - remote"
				"$pod_script_env_file" "${task_name_remote}" "${args[@]}"
			fi
			
			if [ -n "${task_name_local:-}" ]; then
				info "$command ($task_name) - restore - local"
				"$pod_script_env_file" "${task_name_local}" "${args[@]}"
			fi
		fi
		;;
	"setup:verify")
		msg="verify if the directory ${setup_dest_dir_to_verify:-} is empty"
		info "$command ($task_name) - $msg"

		dir_ls="$("$pod_script_env_file" exec-nontty "$toolbox_service" \
			find /"${setup_dest_dir_to_verify}"/ -type f | wc -l)"

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
    re_number='^[0-9]+$'

		if ! [[ $backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="\$msg (value=$backup_delete_old_days)"
			error "$msg"
		fi

		info "$command ($task_name) - start needed services"
		"$pod_script_env_file" up "$toolbox_service"
		
		info "$command ($task_name) - clear old files"
		"$pod_script_env_file" exec-nontty "$toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail
			find /$backup_local_dir/* -ctime +$backup_delete_old_days -delete;
			find /$backup_local_dir/* -maxdepth 0 -type d -ctime \
				+$backup_delete_old_days -exec rm -rf {} \;
		SHELL

		run_tasks "${task_names:-}"
		;;  
	"backup:default")
		info "$command ($task_name) - started"

		if [ -z "${task_name_verify:-}" ]; then
			skip="false"
		else
			info "$command ($task_name) - verify if the backup should be done"
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
			if [ -n "${task_name_local:-}" ]; then
				info "$command ($task_name) - backup - local"
				"$pod_script_env_file" "${task_name_local}" "${args[@]}"
			fi
			
			if [ -n "${task_name_remote:-}" ]; then
				info "$command ($task_name) - backup - remote"
				"$pod_script_env_file" "${task_name_remote}" "${args[@]}"
			fi

			info "$command ($task_name) - start needed services"
			"$pod_script_env_file" up "$toolbox_service"
		fi
		;;
	*)
		error "$command: invalid command"
    ;;
esac
