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
		local ) arg_local="${OPTARG:-}";;
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

		is_compressed_file ) arg_is_compressed_file="${OPTARG:-}";;
		compress_type ) arg_compress_type="${OPTARG:-}";;
		compress_src_file ) arg_compress_src_file="${OPTARG:-}";;
		compress_dest_dir ) arg_compress_dest_dir="${OPTARG:-}";;
		compress_pass ) arg_compress_pass="${OPTARG:-}";;

		recursive_dir ) arg_recursive_dir="${OPTARG:-}";;
		recursive_mode ) arg_recursive_mode="${OPTARG:-}";;
		recursive_mode_dir ) arg_recursive_mode_dir="${OPTARG:-}";;
		recursive_mode_file ) arg_recursive_mode_file="${OPTARG:-}";;
		move_src ) arg_move_src="${OPTARG:-}";;
		move_dest ) arg_move_dest="${OPTARG:-}";;
		file_to_clear ) arg_file_to_clear="${OPTARG:-}";;
		dir_to_clear ) arg_dir_to_clear="${OPTARG:-}";;
		??* ) ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"upgrade")
		info "$command - start"

		info "$command - prepare..."
		"$pod_script_env_file" prepare

		info "$command - build..."
		"$pod_script_env_file" build

		info "$command - setup..."
		"$pod_script_env_file" setup ${args[@]+"${args[@]}"}

		info "$command - ended"
		;;
	"setup")
		if [ -n "${arg_setup_task_name:-}" ]; then
			"$pod_script_env_file" "main:task:$arg_setup_task_name" --local="${arg_local:-}"
		fi

		if [ "$command" = "setup" ]; then
			info "$command - migrate..."
			"$pod_script_env_file" migrate

			info "$command - up..."
			"$pod_script_env_file" up
		fi
		;;
	"setup:default")
		info "$title - start needed services"
		"$pod_script_env_file" up "$arg_toolbox_service"

		if [ -z "${arg_subtask_cmd_verify:-}" ]; then
			skip="false"
		else
			info "$title - verify if the setup should be done"
			skip="$("$pod_script_env_file" "${arg_subtask_cmd_verify}" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd")"
		fi

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="the value of the verification should be true or false"
			error "$title: $msg - result: $skip"
		fi

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		elif [ "${arg_setup_run_new_task:-}" = "true" ]; then
			"$pod_script_env_file" "${arg_subtask_cmd_new}"
		else
			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				if [ "${arg_local:-}" = "true" ]; then
					error "$title - restore - remote cmd with local flag"
				else
					info "$title - restore - remote"
					"$pod_script_env_file" "${arg_subtask_cmd_remote}" \
						--task_name="$arg_task_name" \
						--subtask_cmd="$arg_subtask_cmd"
				fi
			fi

			if [ "${arg_is_compressed_file:-}" = "true" ]; then
				info "$title - restore - uncompress"
				"$pod_script_env_file" "uncompress:$arg_compress_type"\
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--src_file="$arg_compress_src_file" \
					--dest_dir="$arg_compress_dest_dir" \
					--compress_pass="${arg_compress_pass:-}"
			fi

			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail

				function info {
					msg="\$(date '+%F %T') - \${1:-}"
					>&2 echo -e "${GRAY}\${msg}${NC}"
				}

				if [ -n "${arg_recursive_mode:-}" ]; then
					if [ -z "${arg_recursive_dir:-}" ]; then
						error "$title: recursive_dir parameter not specified (recursive_mode=$arg_recursive_mode)"
					fi

					chmod -R "$arg_recursive_mode" "$arg_recursive_dir"
				fi

				if [ -n "${arg_recursive_mode_dir:-}" ]; then
					if [ -z "${arg_recursive_dir:-}" ]; then
						error "$title: recursive_dir parameter not specified (recursive_mode_dir=$arg_recursive_mode_dir)"
					fi

					find "$arg_recursive_dir" -type d -print0 | xargs -0 chmod "$arg_recursive_mode_dir"
				fi

				if [ -n "${arg_recursive_mode_file:-}" ]; then
					if [ -z "${arg_recursive_dir:-}" ]; then
						error "$title: recursive_dir parameter not specified (recursive_mode_file=$arg_recursive_mode_file)"
					fi

					find "$arg_recursive_dir" -type f -print0 | xargs -0 chmod "$arg_recursive_mode_file"
				fi

				if [ -n "${arg_move_src:-}" ]; then
					info "$title: move from ${arg_move_src:-} to ${arg_move_dest:-}"

					if [ -z "${arg_move_dest:-}" ]; then
						error "$title: move_dest parameter not specified (move_src=$arg_move_src)"
					fi

					if [ -d "$arg_move_src" ]; then
						(shopt -s dotglob; mv -v "$arg_move_src"/* "$arg_move_dest")
					else
						mv -v "$arg_move_src" "$arg_move_dest"
					fi
				fi
			SHELL

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$title - restore - local"
				"$pod_script_env_file" "${arg_subtask_cmd_local}" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			fi

			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail

				if [ -n "${arg_file_to_clear:-}" ]; then
					rm -f "$arg_file_to_clear"
				fi

				if [ -n "${arg_dir_to_clear:-}" ]; then
					rm -rf "$arg_dir_to_clear"
				fi
			SHELL
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
		if [ -z "${arg_backup_task_name:-}" ] ; then
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

		"$pod_script_env_file" "main:task:$arg_backup_task_name" --local="${arg_local:-}"
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
			skip="$("$pod_script_env_file" "${arg_subtask_cmd_verify}" ${args[@]+"${args[@]}"})"
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
				"$pod_script_env_file" "${arg_subtask_cmd_local}" ${args[@]+"${args[@]}"}
			fi

			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				if [ "${arg_local:-}" = "true" ]; then
					echo "$title - backup - remote - skipping (local)..."
				else
					info "$title - backup - remote"
					"$pod_script_env_file" "${arg_subtask_cmd_remote}" ${args[@]+"${args[@]}"}
				fi
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
	*)
		error "$command: invalid command"
		;;
esac
