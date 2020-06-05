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
	if [ "$OPT" = "-" ]; then	 # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"			 # extract long option name
		OPTARG="${OPTARG#$OPT}"	 # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"			# if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
		subtask_cmd_verify ) arg_subtask_cmd_verify="${OPTARG:-}";;
		subtask_cmd_remote ) arg_subtask_cmd_remote="${OPTARG:-}";;
		subtask_cmd_local ) arg_subtask_cmd_local="${OPTARG:-}";;
		subtask_cmd_new ) arg_subtask_cmd_new="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;

		setup_task_name ) arg_setup_task_name="${OPTARG:-}";;
		setup_run_new_task ) arg_setup_run_new_task="${OPTARG:-}";;
		setup_dest_dir_to_verify ) arg_setup_dest_dir_to_verify="${OPTARG:-}";;

		backup_task_name ) arg_backup_task_name="${OPTARG:-}";;
		backup_local_base_dir ) arg_backup_local_base_dir="${OPTARG:-}";;
		backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		backup_delete_old_days ) arg_backup_delete_old_days="${OPTARG:-}";;
		??* ) ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

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
		if [ -n "${arg_setup_task_name:-}" ]; then
			"$pod_script_env_file" "main:task:$arg_setup_task_name"
		fi

		if [ "$command" = "setup" ]; then
			"$pod_script_env_file" migrate "${args[@]}"
		fi
		;;
	"setup:default")
		info "$title - start needed services"
		"$pod_script_env_file" up "$arg_toolbox_service"

		msg="verify if the setup should be done"
		info "$title - $msg"
		skip="$("$pod_script_env_file" "$arg_subtask_cmd_verify" "${args[@]}")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$title: $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		elif [ "${arg_setup_run_new_task:-}" = "true" ]; then
			"$pod_script_env_file" "${arg_subtask_cmd_new}"
		else
			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				info "$title - restore - remote"
				"$pod_script_env_file" "${arg_subtask_cmd_remote}" "${args[@]}"
			fi

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$title - restore - local"
				"$pod_script_env_file" "${arg_subtask_cmd_local}" "${args[@]}"
			fi
		fi
		;;
	"setup:verify")
		msg="verify if the directory ${arg_setup_dest_dir_to_verify:-} is empty"
		info "$title - $msg"

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail

			function info {
				msg="\$(date '+%F %T') - \${1:-}"
				>&2 echo -e "${GRAY}$command: \${msg}${NC}"
			}

			function error {
				msg="\$(date '+%F %T') \${1:-}"
				>&2 echo -e "${RED}$command: \${msg}${NC}"
				exit 2
			}

			dir_ls=""

			if [ -d "$arg_setup_dest_dir_to_verify" ]; then
				dir_ls="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					find "${arg_setup_dest_dir_to_verify}"/ -type f | wc -l)"
			else
				msg="$command: setup_dest_dir_to_verify ($arg_setup_dest_dir_to_verify)"
				msg="\$msg is not a directory (inside the service $arg_toolbox_service)"
				error "\$msg"
			fi

			if [ -z "\$dir_ls" ]; then
				dir_ls="0"
			fi

			if [[ \$dir_ls -ne 0 ]]; then
				echo "true"
			else
				echo "false"
			fi
		SHELL
		;;
	"backup")
		if [ -z "${arg_task_cmds:-}" ] ; then
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

		"$pod_script_env_file" "main:task:$arg_backup_task_name"
		;;
	"backup:default")
		info "$title - started"

		if [ -z "${arg_backup_local_dir:-}" ] ; then
			msg="The variable 'backup_local_dir' is not defined"
			error "$title: $msg"
		fi

		if [ -z "${arg_backup_delete_old_days:-}" ] ; then
			msg="The variable 'backup_delete_old_days' is not defined"
			error "$title: $msg"
		fi

		re_number='^[0-9]+$'

		if ! [[ $arg_backup_delete_old_days =~ $re_number ]] ; then
			msg="The variable 'backup_delete_old_days' should be a number"
			msg="$msg (value=$arg_backup_delete_old_days)"
			error "$title: $msg"
		fi

		if [ -z "${arg_subtask_cmd_verify:-}" ]; then
			skip="false"
		else
			info "$title - verify if the backup should be done"
			skip="$("$pod_script_env_file" "${arg_subtask_cmd_verify}" "${args[@]}")"
		fi

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="value of the verification should be true or false"
			msg="$msg - result: $skip"
			error "$title: $msg"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		else
			info "$command - start needed services"
			"$pod_script_env_file" up "$arg_toolbox_service"

			msg="create the backup directory (if there isn't yet)"
			info "$command - $msg ($arg_backup_local_dir)"
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				mkdir -p "$arg_backup_local_dir"

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$title - backup - local"
				"$pod_script_env_file" "${arg_subtask_cmd_local}" "${args[@]}"
			fi

			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				info "$title - backup - remote"
				"$pod_script_env_file" "${arg_subtask_cmd_remote}" "${args[@]}"
			fi

			info "$title - clear old files"
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
		if [ -z "${arg_task_cmds:-}" ] ; then
			info "$command: no tasks defined - skipping..."
			exit 0
		fi

		# main command - run verify sub-tasks
		run_tasks "${arg_task_cmds:-}"
		;;
	*)
		error "$command: invalid command"
		;;
esac
