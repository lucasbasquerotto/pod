#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2153
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

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=( "$@" )

# shellcheck disable=SC2214
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
		verify_file_to_skip ) arg_verify_file_to_skip="${OPTARG:-}";;
		subtask_cmd_verify ) arg_subtask_cmd_verify="${OPTARG:-}";;
		subtask_cmd_remote ) arg_subtask_cmd_remote="${OPTARG:-}";;
		subtask_cmd_local ) arg_subtask_cmd_local="${OPTARG:-}";;
		subtask_cmd_new ) arg_subtask_cmd_new="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;

		setup_task_name ) arg_setup_task_name="${OPTARG:-}";;
		setup_run_new_task ) arg_setup_run_new_task="${OPTARG:-}";;
		setup_dest_dir_to_verify ) arg_setup_dest_dir_to_verify="${OPTARG:-}";;

		backup_task_name ) arg_backup_task_name="${OPTARG:-}";;
		backup_is_delete_old ) arg_backup_is_delete_old="${OPTARG:-}";;
		backup_date_format ) arg_backup_date_format="${OPTARG:-}";;
		backup_time_format ) arg_backup_time_format="${OPTARG:-}";;
		backup_datetime_format ) arg_backup_datetime_format="${OPTARG:-}";;

		is_compressed_file ) arg_is_compressed_file="${OPTARG:-}";;
		compress_type ) arg_compress_type="${OPTARG:-}";;
		compress_src_file ) arg_compress_src_file="${OPTARG:-}";;
		compress_src_dir ) arg_compress_src_dir="${OPTARG:-}";;
		compress_dest_file ) arg_compress_dest_file="${OPTARG:-}";;
		compress_dest_dir ) arg_compress_dest_dir="${OPTARG:-}";;
		compress_flat ) arg_compress_dest_dir="${OPTARG:-}";;
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

function verify {
	skip=''
	skip_file=''

	if [ -n "${arg_subtask_cmd_verify:-}" ]; then
		info "$title - verify if the task should be done"
		skip="$("$pod_script_env_file" "${arg_subtask_cmd_verify}" \
			--task_name="$arg_task_name" \
			--subtask_cmd="$arg_subtask_cmd" \
			--local="${arg_local:-}")"

		if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
			msg="the value of the verification should be true or false"
			error "$title: $msg - result: $skip"
		fi
	fi

	if [ -n "${arg_verify_file_to_skip:-}" ]; then
		skip_file="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
			test -f "$arg_verify_file_to_skip" && echo "true" || echo "false"
		SHELL
		)"
	fi

	if [ -n "$skip" ] && [ -n "$skip_file" ]; then
		if [ "$skip" != "$skip_file" ]; then
			msg="the value of the verification command and the file verification should be the same"

			if [ "$skip_file" = "false" ]; then
				msg="$msg (you can create the file ${arg_verify_file_to_skip:-} inside the toolbox service to skip the task)"
			elif [ "$skip_file" = "true" ]; then
				msg="$msg (you can remove the file ${arg_verify_file_to_skip:-} inside the toolbox service to not skip the task)"
			fi

			error "$title: $msg - skip: $skip, skip_file: $skip_file"
		fi
	fi

	skip="${skip:-$skip_file}"
	skip="${skip:-false}"

	echo "$skip"
}

function general_actions {
	move_dest="$1"

	"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
		set -eou pipefail

		function info {
			msg="\$(date '+%F %T') - \${1:-}"
			>&2 echo -e "${GRAY}\${msg}${NC}"
		}

		if [ -n "${arg_move_src:-}" ]; then
			info "$title: move from ${arg_move_src:-} to ${move_dest:-}"

			if [ -z "${move_dest:-}" ]; then
				error "$title: move_dest parameter not specified (move_src=$arg_move_src)"
			fi

			if [ -d "$arg_move_src" ]; then
				(shopt -s dotglob; mv -v "$arg_move_src"/* "$move_dest")
			else
				mv -v "$arg_move_src" "$move_dest"
			fi
		fi

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
	SHELL
}

function final_actions {
	"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
		set -eou pipefail

		if [ -n "${arg_file_to_clear:-}" ]; then
			rm -f "$arg_file_to_clear"
		fi

		if [ -n "${arg_dir_to_clear:-}" ]; then
			rm -rf "$arg_dir_to_clear"
		fi

		if [ -n "${arg_verify_file_to_skip:-}" ]; then
			mkdir -p "\$(dirname $arg_verify_file_to_skip)"
			touch "${arg_verify_file_to_skip:-}"
		fi
	SHELL
}

case "$command" in
	"upgrade")
		info "$command - start"

		info "$command - build..."
		"$pod_script_env_file" build

		info "$command - prepare..."
		"$pod_script_env_file" prepare

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

		skip="$(verify)"

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
				"$pod_script_env_file" "run:uncompress:$arg_compress_type"\
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--src_file="$arg_compress_src_file" \
					--dest_dir="$arg_compress_dest_dir" \
					--compress_pass="${arg_compress_pass:-}"
			fi

			general_actions "${arg_move_dest:-}";

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$title - restore - local"
				"$pod_script_env_file" "${arg_subtask_cmd_local}" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			fi

			final_actions;
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
		status=0

		if [ -z "${arg_backup_task_name:-}" ] ; then
			info "$command: no backup task defined..."
		else
			"$pod_script_env_file" "main:task:$arg_backup_task_name" \
				--local="${arg_local:-}" && status=$? || status=$?
		fi

		if [ "${arg_backup_is_delete_old:-}" = "true" ] ; then
			"$pod_script_env_file" "delete:old"
		fi

		if [[ $status -ne 0 ]]; then
			error "${1:-} - exited with status $status"
		fi
		;;
	"backup:default")
		info "$title - started"

		skip="$(verify)"

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		else
			info "$command - start the needed services"
			"$pod_script_env_file" up "$arg_toolbox_service"

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$title - backup - local"
				"$pod_script_env_file" "${arg_subtask_cmd_local}" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			fi

			if [ "${arg_is_compressed_file:-}" = "true" ]; then
				if [ -z "${arg_compress_src_file:-}" ] && [ -z "${arg_compress_src_dir:-}" ]; then
					error "$title: compress_src_file and compress_src_dir parameters are both empty"
				elif [ -n "${arg_compress_src_file:-}" ] && [ -n "${arg_compress_src_dir:-}" ]; then
					error "$title: compress_src_file and compress_src_dir parameters are both specified"
				fi

				if [ -n "${arg_compress_src_file:-}" ]; then
					task_kind="file"
				else
					task_kind="dir"
				fi

				dest_file="$("$pod_script_env_file" "run:util:replace_placeholders" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--value="$arg_compress_dest_file" \
					--date_format="${arg_backup_date_format:-}" \
					--time_format="${arg_backup_time_format:-}" \
					--datetime_format="${arg_backup_datetime_format:-}")" \
					|| error "$command: replace_placeholders (dest_file)"

				info "$title - backup - compress"
				"$pod_script_env_file" "run:compress:$arg_compress_type" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--task_kind="$task_kind" \
					--src_file="${arg_compress_src_file:-}" \
					--src_dir="${arg_compress_src_dir:-}" \
					--dest_file="$dest_file" \
					--flat="${arg_compress_flat:-}" \
					--compress_pass="${arg_compress_pass:-}"
			fi

			move_dest="${arg_move_dest:-}"

			if [ -n "${move_dest:-}" ]; then
				move_dest="$("$pod_script_env_file" "run:util:replace_placeholders" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--value="$move_dest" \
					--date_format="${arg_backup_date_format:-}" \
					--time_format="${arg_backup_time_format:-}" \
					--datetime_format="${arg_backup_datetime_format:-}")" \
					|| error "$command: replace_placeholders (move_dest)"
			fi

			general_actions "$move_dest";

			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				if [ "${arg_local:-}" = "true" ]; then
					echo "$title - backup - remote - skipping (local)..."
				else
					info "$title - backup - remote"
					"$pod_script_env_file" "${arg_subtask_cmd_remote}" \
						--task_name="$arg_task_name" \
						--subtask_cmd="$arg_subtask_cmd"
				fi
			fi

			final_actions;
		fi
		;;
	*)
		error "$command: invalid command"
		;;
esac
