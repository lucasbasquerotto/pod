#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

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

args=("$@")

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		task_kind ) arg_task_kind="${OPTARG:-}";;
		src_file ) arg_src_file="${OPTARG:-}";;
		src_dir ) arg_src_dir="${OPTARG:-}";;
		dest_file ) arg_dest_file="${OPTARG:-}";;
		dest_dir ) arg_dest_dir="${OPTARG:-}";;
		flat ) arg_flat="${OPTARG:-}";;
		compress_pass ) arg_compress_pass="${OPTARG:-}";;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"compress:zip")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:compress:zip" ${args[@]+"${args[@]}"}
		;;
	"inner:compress:zip")
		if [ -z "${arg_dest_file:-}" ]; then
			error "$title: dest_file parameter not specified"
		fi

		if [ -z "${arg_src_file:-}" ] && [ -z "${arg_src_dir:-}" ]; then
			error "$title: src_file and src_dir parameters are both empty"
		elif [ -n "${arg_src_file:-}" ] && [ -n "${arg_src_dir:-}" ]; then
			error "$title: src_file and src_dir parameters are both specified"
		fi

		extension="${arg_dest_file##*.}"
		expected_extension="zip"

		if [ "$extension" != "$expected_extension" ]; then
			error "$title - wrong extension: $extension (expected: $expected_extension)"
		fi

		zip_opts=()

		if [ -n "${arg_compress_pass:-}" ]; then
			zip_opts=( "--password" "$arg_compress_pass" )
		fi

		dest_file_base_dir="$(dirname "$arg_dest_file")"

		if [ ! -d "$dest_file_base_dir" ]; then
			mkdir -p "$dest_file_base_dir"
		fi

		if [ "$arg_task_kind" = "dir" ]; then
			msg="$arg_src_dir to $arg_dest_file"
			info "$command - compress directory - $msg"

			if [ "${arg_flat:-}" = "true" ]; then
				cd "$arg_src_dir"
				zip -r ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" ./
			else
				base_dir="$(dirname "$arg_src_dir")"
				main_dir="$(basename "$arg_src_dir")"
				cd "$base_dir"
				zip -r ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" ./"$main_dir"
			fi
		elif [ "$arg_task_kind" = "file" ]; then
			msg="$arg_src_file to $arg_dest_file"

			if [ "$arg_src_file" != "$arg_dest_file" ]; then
				if [ "${arg_src_file##*.}" = "$expected_extension" ]; then
					info "$command - move file - $msg"
					mv "$arg_src_file" "$arg_dest_file"
				else
					info "$command - compress file - $msg"
					zip -j ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" "$arg_src_file"
				fi
			fi
		else
			error "$title: $arg_task_kind: task_kind invalid value"
		fi
		;;
	"uncompress:zip")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:uncompress:zip" ${args[@]+"${args[@]}"}
		;;
	"inner:uncompress:zip")
		if [ -z "${arg_src_file:-}" ]; then
			error "$title: src_file parameter not specified"
		fi

		if [ -z "${arg_dest_dir:-}" ]; then
			error "$title: dest_dir parameter is empty"
		fi

		extension="${arg_src_file##*.}"
		expected_extension="zip"

		if [ "$extension" != "$expected_extension" ]; then
			error "$title - wrong extension: $extension (expected: $expected_extension)"
		fi

		zip_opts=()

		if [ -n "${arg_compress_pass:-}" ]; then
			zip_opts=( "-P" "$arg_compress_pass" )
		fi

		if [ ! -d "$arg_dest_dir" ]; then
			mkdir -p "$arg_dest_dir"
		fi

		msg="$arg_src_file to $arg_dest_dir"
		info "$command - uncompress file - $msg"
		unzip -o ${zip_opts[@]+"${zip_opts[@]}"} "$arg_src_file" -d "$arg_dest_dir"
		;;
	*)
		error "$title: invalid command"
		;;
esac
