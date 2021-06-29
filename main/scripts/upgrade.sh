#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

pod_script_same_file="$pod_layer_dir/main/scripts/upgrade.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=( "$@" )

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then    # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"      # extract long option name
		OPTARG="${OPTARG#$OPT}"  # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"     # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
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
		backup_no_src_needed ) arg_backup_no_src_needed="${OPTARG:-}";;
		backup_src ) arg_backup_src="${OPTARG:-}";;
		backup_is_delete_old ) arg_backup_is_delete_old="${OPTARG:-}";;
		backup_date_format ) arg_backup_date_format="${OPTARG:-}";;
		backup_time_format ) arg_backup_time_format="${OPTARG:-}";;
		backup_datetime_format ) arg_backup_datetime_format="${OPTARG:-}";;

		is_compressed_file ) arg_is_compressed_file="${OPTARG:-}";;
		compress_type ) arg_compress_type="${OPTARG:-}";;
		compress_src_file ) arg_compress_src_file="${OPTARG:-}";;
		compress_dest_file ) arg_compress_dest_file="${OPTARG:-}";;
		compress_dest_dir ) arg_compress_dest_dir="${OPTARG:-}";;
		compress_flat ) arg_compress_flat="${OPTARG:-}";;
		compress_pass ) arg_compress_pass="${OPTARG:-}";;

		recursive_dir ) arg_recursive_dir="${OPTARG:-}";;
		recursive_mode ) arg_recursive_mode="${OPTARG:-}";;
		recursive_mode_dir ) arg_recursive_mode_dir="${OPTARG:-}";;
		recursive_mode_file ) arg_recursive_mode_file="${OPTARG:-}";;
		move_src ) arg_move_src="${OPTARG:-}";;
		move_dest ) arg_move_dest="${OPTARG:-}";;
		file_to_clear ) arg_file_to_clear="${OPTARG:-}";;
		dir_to_clear ) arg_dir_to_clear="${OPTARG:-}";;

		inner_move_dest ) arg_inner_move_dest="${OPTARG:-}";;
		??* ) ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"upgrade"|"fast-upgrade")
		info "$command - start"

		if [ "$command" != "fast-upgrade" ]; then
			info "$command - build..."
			"$pod_script_env_file" build
		fi

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
		info "$command - start needed services"
		"$pod_script_env_file" up "$arg_toolbox_service"

		skip="$("$pod_script_same_file" "upgrade:inner:verify" "${args[@]}")"

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		else
			if [ "${arg_setup_run_new_task:-}" = "true" ]; then
				"$pod_script_env_file" "${arg_subtask_cmd_new}" \
					--task_info="$title" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd"
			else
				if [ -n "${arg_subtask_cmd_remote:-}" ]; then
					if [ "${arg_local:-}" = "true" ]; then
						error "$title - restore - remote cmd with local flag"
					else
						info "$command - restore - remote"
						"$pod_script_env_file" "${arg_subtask_cmd_remote}" \
							--task_info="$title" \
							--task_name="$arg_task_name" \
							--subtask_cmd="$arg_subtask_cmd"
					fi
				fi

				if [ "${arg_is_compressed_file:-}" = "true" ]; then
					info "$command - restore - uncompress"
					"$pod_script_env_file" "run:uncompress:$arg_compress_type"\
						--task_info="$title" \
						--toolbox_service="$arg_toolbox_service" \
						--src_file="$arg_compress_src_file" \
						--dest_dir="$arg_compress_dest_dir" \
						--compress_pass="${arg_compress_pass:-}"
				fi

				"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					bash "$inner_run_file" "inner:upgrade:general_actions" \
					--inner_move_dest="${arg_move_dest:-}" \
					${args[@]+"${args[@]}"}

				if [ -n "${arg_subtask_cmd_local:-}" ]; then
					info "$command - restore - local"
					"$pod_script_env_file" "${arg_subtask_cmd_local}" \
						--task_info="$title" \
						--task_name="$arg_task_name" \
						--subtask_cmd="$arg_subtask_cmd"
				fi
			fi

			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:upgrade:final_actions" \
				${args[@]+"${args[@]}"}
		fi
		;;
	"setup:verify:default")
		msg="verify if the directory ${arg_setup_dest_dir_to_verify:-} is empty"
		info "$command - $msg"

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:setup:verify:default" ${args[@]+"${args[@]}"}
		;;
	"inner:setup:verify:default")
		dir_ls=""

		unknown_code error

		if [ -d "$arg_setup_dest_dir_to_verify" ]; then
			dir_ls="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				find "${arg_setup_dest_dir_to_verify}"/ -type f | wc -l)"
		else
			msg="$command: setup_dest_dir_to_verify ($arg_setup_dest_dir_to_verify)"
			msg="$msg is not a directory (inside the service $arg_toolbox_service)"
			error "$msg"
		fi

		if [ -z "$dir_ls" ]; then
			dir_ls="0"
		fi

		aaa

		if [[ $dir_ls -ne 0 ]]; then
			echo "true"
		else
			echo "false"
		fi
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
		info "$command - started"

		skip="$("$pod_script_same_file" "upgrade:inner:verify" "${args[@]}")"

		if [ "$skip" = "true" ]; then
			echo "$(date '+%F %T') - $command ($arg_subtask_cmd) - skipping..."
		else
			info "$command - start the needed services"
			"$pod_script_env_file" up "$arg_toolbox_service"

			backup_src="${arg_backup_src:-}"

			if [ -n "${arg_subtask_cmd_local:-}" ]; then
				info "$command - backup - local"
				backup_src_local="$("$pod_script_env_file" "${arg_subtask_cmd_local}" \
					--task_info="$title" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$arg_subtask_cmd")"

				if [ -z "${backup_src:-}" ] && [ -z "${backup_src_local:-}" ]; then
					if [ "${arg_backup_no_src_needed:-}" != 'true' ]; then
						msg="backup_src and the result of subtask_cmd_local are both empty"
						error "$title: $msg"
					fi
				elif [ -n "${backup_src:-}" ] && [ -n "${backup_src_local:-}" ]; then
					msg="backup_src (${backup_src:-})"
					msg="$msg and the result of subtask_cmd_local ($backup_src_local)"
					msg="$msg are both specified"
					error "$title: $msg"
				elif [ -z "${backup_src:-}" ]; then
					backup_src="${backup_src_local:-}"
				fi
			elif [ -z "${backup_src:-}" ]; then
				if [ "${arg_backup_no_src_needed:-}" != 'true' ]; then
					msg="backup_src and subtask_cmd_local are both empty"
					error "$title: $msg"
				fi
			fi

			next_src_file=''
			next_src_dir=''

			if [ -n "${backup_src:-}" ]; then
				src_type="$("$pod_script_env_file" "run:util:file:type" \
					--task_info="$title" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--path="$backup_src" \
					|| error "$title: file:type (dest_file)"
				)"

				if [ "${src_type:-}" = 'file' ]; then
					next_src_file="${backup_src:-}"
				elif [ "${src_type:-}" = 'dir' ]; then
					next_src_dir="${backup_src:-}"
				else
					error "$title: invalid backup source type (${src_type:-})"
				fi
			fi

			if [ "${arg_is_compressed_file:-}" = "true" ]; then
				if [ -z "${backup_src:-}" ]; then
					msg="backup_src is empty when trying to compress"
					msg="$msg the file/directory during the backup"
					error "$title: $msg"
				fi

				dest_file="$("$pod_script_env_file" "run:util:replace_placeholders" \
					--task_info="$title" \
					--task_name="$arg_task_name" \
					--subtask_cmd="$command" \
					--toolbox_service="$arg_toolbox_service" \
					--value="$arg_compress_dest_file" \
					--date_format="${arg_backup_date_format:-}" \
					--time_format="${arg_backup_time_format:-}" \
					--datetime_format="${arg_backup_datetime_format:-}")" \
					|| error "$title: replace_placeholders (dest_file)"

				info "$command - backup - compress"
				"$pod_script_env_file" "run:compress:$arg_compress_type" \
					--task_info="$title" \
					--toolbox_service="$arg_toolbox_service" \
					--task_kind="$src_type" \
					--src_file="${next_src_file:-}" \
					--src_dir="${next_src_dir:-}" \
					--dest_file="$dest_file" \
					--flat="${arg_compress_flat:-}" \
					--compress_pass="${arg_compress_pass:-}"

				next_src_file="${dest_file:-}"
				next_src_dir=''
			fi

			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:upgrade:general_actions" \
				${args[@]+"${args[@]}"}

			if [ -n "${arg_subtask_cmd_remote:-}" ]; then
				if [ "${arg_local:-}" = "true" ]; then
					echo "$title - backup - remote - skipping (local)..."
				else
					info "$command - backup - remote"
					"$pod_script_env_file" "${arg_subtask_cmd_remote}" \
						--task_info="$title" \
						--task_name="$arg_task_name" \
						--subtask_cmd="$arg_subtask_cmd" \
						--src_dir="${next_src_dir:-}" \
						--src_file="${next_src_file:-}"
				fi
			fi

			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:upgrade:final_actions" \
				${args[@]+"${args[@]}"}
		fi
		;;
	"upgrade:inner:verify")
		skip=''
		skip_file=''

		if [ -n "${arg_subtask_cmd_verify:-}" ]; then
			info "$command - verify if the task should be done"
			skip="$("$pod_script_env_file" "${arg_subtask_cmd_verify}" \
				--task_info="$title" \
				--task_name="$arg_task_name" \
				--subtask_cmd="$arg_subtask_cmd" \
				--local="${arg_local:-}")"

			if [ "$skip" != "true" ] && [ "$skip" != "false" ]; then
				msg="the value of the verification should be true or false"
				error "$title: $msg - result: $skip"
			fi
		fi

		if [ -n "${arg_verify_file_to_skip:-}" ]; then
			skip_file="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:upgrade:verify:file_to_skip" ${args[@]+"${args[@]}"})"
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
		;;
	"inner:upgrade:verify:file_to_skip")
		test -f "$arg_verify_file_to_skip" && echo "true" || echo "false"
		;;
	"inner:upgrade:general_actions")
		if [ -n "${arg_move_src:-}" ]; then
			>&2 echo "move from ${arg_move_src:-} to ${arg_inner_move_dest:-}"

			if [ -z "${arg_inner_move_dest:-}" ]; then
				error "$title: inner_move_dest parameter not specified (move_src=${arg_move_src:-})"
			fi

			if [ -d "${arg_move_src:-}" ]; then
				(shopt -s dotglob; mv -v "${arg_move_src:-}"/* "${arg_inner_move_dest:-}")
			else
				mv -v "${arg_move_src:-}" "${arg_inner_move_dest:-}"
			fi
		fi

		if [ -n "${arg_recursive_mode:-}" ]; then
			if [ -z "${arg_recursive_dir:-}" ]; then
				error "$title: recursive_dir parameter not specified (recursive_mode=${arg_recursive_mode:-})"
			fi

			>&2 echo "define mode to files and directories at ${arg_recursive_dir:-}"
			chmod -R "${arg_recursive_mode:-}" "${arg_recursive_dir:-}"
		fi

		if [ -n "${arg_recursive_mode_dir:-}" ]; then
			if [ -z "${arg_recursive_dir:-}" ]; then
				error "$title: recursive_dir parameter not specified (recursive_mode_dir=${arg_recursive_mode_dir:-})"
			fi

			>&2 echo "define mode to directories at ${arg_recursive_dir:-}"
			find "${arg_recursive_dir:-}" -type d -print0 | xargs -r0 chmod "${arg_recursive_mode_dir:-}"
		fi

		if [ -n "${arg_recursive_mode_file:-}" ]; then
			if [ -z "${arg_recursive_dir:-}" ]; then
				error "$title: recursive_dir parameter not specified (recursive_mode_file=${arg_recursive_mode_file:-})"
			fi

			>&2 echo "define mode to files at ${arg_recursive_dir:-}"
			find "${arg_recursive_dir:-}" -type f -print0 | xargs -r0 chmod "${arg_recursive_mode_file:-}"
		fi
		;;
	"inner:upgrade:final_actions")
		if [ -n "${arg_file_to_clear:-}" ]; then
			rm -f "${arg_file_to_clear:-}"
		fi

		if [ -n "${arg_dir_to_clear:-}" ]; then
			rm -rf "${arg_dir_to_clear:-}"
		fi

		if [ -n "${arg_verify_file_to_skip:-}" ]; then
			mkdir -p "$(dirname "${arg_verify_file_to_skip:-}")"
			touch "${arg_verify_file_to_skip:-}"
		fi
		;;
	*)
		error "$title: invalid command"
		;;
esac
