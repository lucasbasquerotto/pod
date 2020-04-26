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
		task_names ) arg_task_names="${OPTARG:-}";;

		task_name ) arg_task_name="${OPTARG:-}";; 
		task_name_verify ) arg_task_name_verify="${OPTARG:-}";; 
		task_name_remote ) arg_task_name_remote="${OPTARG:-}";; 
		task_name_local ) arg_task_name_local="${OPTARG:-}";; 
		task_name_new ) arg_task_name_new="${OPTARG:-}";; 
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;

		setup_run_new_task ) arg_setup_run_new_task="${OPTARG:-}";;    
		setup_dest_dir_to_verify ) arg_setup_dest_dir_to_verify="${OPTARG:-}";;
		
		backup_local_base_dir ) arg_backup_local_base_dir="${OPTARG:-}";;
		backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		backup_delete_old_days ) arg_backup_delete_old_days="${OPTARG:-}";;
		??* ) ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

function run_tasks {
  run_task_names="${1:-}" 

	info "run_task_names: $run_task_names"

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
	"upgrade"|"fast-upgrade"|"update"|"fast-update")
		if [ "$command" != "fast-upgrade" ]; then
			info "$command - prepare..."
			"$pod_script_env_file" prepare
		fi
		
		info "$command - build..."
		"$pod_script_env_file" build

		if [[ "$command" = @("upgrade"|"fast-upgrade") ]]; then
			info "$command - setup..."
			"$pod_script_env_file" setup "${args[@]}"
		elif [ "$command" = "update" ]; then
			info "$command - migrate..."
			"$pod_script_env_file" migrate "${args[@]}" 
		fi
		
		info "$command - run..."
		"$pod_script_env_file" up
		info "$command - ended"
		;;
	"setup"|"fast-setup")    
		run_tasks "${arg_task_names:-}"

    if [ "$command" = "setup" ]; then
      "$pod_script_env_file" migrate "${args[@]}" 
    fi
		;;
	"setup:default")
		info "$command ($arg_task_name) - start needed services"
		"$pod_script_env_file" up "$arg_toolbox_service"

		msg="verify if the setup should be done"
		info "$command ($arg_task_name) - $msg "
		skip="$("$pod_script_env_file" "${arg_task_name_verify}" "${args[@]}")"
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$command ($arg_task_name): $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_task_name) - skipping..."
		elif [ "${arg_setup_run_new_task:-}" = "true" ]; then
			"$pod_script_env_file" "${arg_task_name_new}"
		else 
			if [ -n "${arg_task_name_remote:-}" ]; then
				info "$command ($arg_task_name) - restore - remote"
				"$pod_script_env_file" "${arg_task_name_remote}" "${args[@]}"
			fi
			
			if [ -n "${arg_task_name_local:-}" ]; then
				info "$command ($arg_task_name) - restore - local"
				"$pod_script_env_file" "${arg_task_name_local}" "${args[@]}"
			fi
		fi
		;;
	"setup:verify")
		msg="verify if the directory ${arg_setup_dest_dir_to_verify:-} is empty"
		info "$command ($arg_task_name) - $msg"

		dir_ls="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			find "${arg_setup_dest_dir_to_verify}"/ -type f | wc -l)"

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
		if [ -z "${arg_task_names:-}" ] ; then
			info "$command: no tasks defined - skipping..."
			exit 0
		fi

		if [ -z "${arg_backup_local_base_dir:-}" ] ; then
			msg="The variable 'backup_local_base_dir' is not defined"
			error "$command: $msg"
		fi

		if [ -z "${arg_backup_local_dir:-}" ] ; then
			msg="The variable 'backup_local_dir' is not defined"
			error "$command: $msg"
		fi

		if [ -z "${arg_backup_delete_old_days:-}" ] ; then
			msg="The variable 'backup_delete_old_days' is not defined"
			error "$command: $msg"
		fi

    re_number='^[0-9]+$'

		if ! [[ $arg_backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="$msg (value=$arg_backup_delete_old_days)"
			error "$command: $msg"
		fi

		info "$command - start needed services"
		"$pod_script_env_file" up "$arg_toolbox_service"
		
		info "$command - create the backup base directory and clear old files"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail
			mkdir -p "$arg_backup_local_base_dir"
			
			# remove old files and directories
			find "$arg_backup_local_base_dir"/ -mindepth 1 \
				-ctime +$arg_backup_delete_old_days -delete -print;
				
			# remove old and empty directories
			find "$arg_backup_local_base_dir"/ -mindepth 1 -type d \
				-ctime +$arg_backup_delete_old_days -empty -delete -print;
		SHELL

		# main command - run backup sub-tasks
		run_tasks "${arg_task_names:-}"
		;;  
	"backup:default")
		info "$command ($arg_task_name) - started"

		if [ -z "${arg_backup_local_dir:-}" ] ; then
			msg="The variable 'backup_local_dir' is not defined"
			error "$command ($arg_task_name): $msg"
		fi

		if [ -z "${arg_backup_delete_old_days:-}" ] ; then
			msg="The variable 'backup_delete_old_days' is not defined"
			error "$command ($arg_task_name): $msg"
		fi

    re_number='^[0-9]+$'

		if ! [[ $arg_backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="$msg (value=$arg_backup_delete_old_days)"
			error "$command ($arg_task_name): $msg"
		fi

		if [ -z "${arg_task_name_verify:-}" ]; then
			skip="false"
		else
			info "$command ($arg_task_name) - verify if the backup should be done"
			skip="$("$pod_script_env_file" "${arg_task_name_verify}" "${args[@]}")"
		fi
      
		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$command ($arg_task_name): $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_task_name) - skipping..."
		else
			info "$command - start needed services"
			"$pod_script_env_file" up "$arg_toolbox_service"

			msg="create the backup directory (if there isn't yet)"
			info "$command - $msg ($arg_backup_local_dir)"
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				mkdir -p "$arg_backup_local_dir"
			
			if [ -n "${arg_task_name_local:-}" ]; then
				info "$command ($arg_task_name) - backup - local"
				"$pod_script_env_file" "${arg_task_name_local}" "${args[@]}"
			fi
			
			if [ -n "${arg_task_name_remote:-}" ]; then
				info "$command ($arg_task_name) - backup - remote"
				"$pod_script_env_file" "${arg_task_name_remote}" "${args[@]}"
			fi
			
			info "$command ($arg_task_name) - clear old files"
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail
				
				# remove old files and directories
				find "$arg_backup_local_dir"/ -mindepth 1 \
					-ctime +$arg_backup_delete_old_days -delete -print;
					
				# remove old and empty directories
				find "$arg_backup_local_dir"/ -mindepth 1 -type d \
					-ctime +$arg_backup_delete_old_days -empty -delete -print;
			SHELL
		fi
		;;
	"verify")	
		if [ -z "${arg_task_names:-}" ] ; then
			info "$command: no tasks defined - skipping..."
			exit 0
		fi

		# main command - run verify sub-tasks
		run_tasks "${arg_task_names:-}"
		;;  
	*)
		error "$command: invalid command"
    ;;
esac
