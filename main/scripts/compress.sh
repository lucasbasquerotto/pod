#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

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

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
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

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"compress:zip")
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

		if [ "$arg_task_kind" = "dir" ]; then
			msg="$arg_src_dir to $arg_dest_file (inside toolbox)"
			info "$title - compress directory - $msg"
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail

				if [ "${arg_flat:-}" = "true" ]; then
					cd "$arg_src_dir"
					zip -r ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" ./
				else
					base_dir="$(dirname "$arg_src_dir")"
					main_dir="$(basename "$arg_src_dir")"
					cd "\$base_dir"
					zip -r ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" ./"\$main_dir"
				fi
			SHELL
		elif [ "$arg_task_kind" = "file" ]; then
			msg="$arg_src_file to $arg_dest_file (inside toolbox)"

			if [ "$arg_src_file" != "$arg_dest_file" ]; then
				if [ "${arg_src_file##*.}" = "$expected_extension" ]; then
					info "$title - move file - $msg"
					>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
						mv "$arg_src_file" "$arg_dest_file"
				else
					info "$title - compress file - $msg"
					>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
						zip -j ${zip_opts[@]+"${zip_opts[@]}"} "$arg_dest_file" "$arg_src_file"
				fi
			fi
		else
			error "$title: $arg_task_kind: task_kind invalid value"
		fi
		;;
	"uncompress:zip")
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

		msg="$arg_src_file to $arg_dest_dir (inside toolbox)"
		info "$title - uncompress file - $msg"
		>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			unzip -o ${zip_opts[@]+"${zip_opts[@]}"} "$arg_src_file" -d "$arg_dest_dir"
		;;
	*)
		error "$title: invalid command"
		;;
esac
