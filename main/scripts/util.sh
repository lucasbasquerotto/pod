#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then    # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"      # extract long option name
		OPTARG="${OPTARG#$OPT}"  # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"     # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		title ) arg_title="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;

		error ) arg_error="${OPTARG:-}";;
		warn ) arg_warn="${OPTARG:-}";;
		info ) arg_info="${OPTARG:-}";;
		start ) arg_start="${OPTARG:-}";;
		end ) arg_end="${OPTARG:-}";;

		no_info ) arg_no_info="${OPTARG:-}";;
		no_warn ) arg_no_warn="${OPTARG:-}";;
		no_error ) arg_no_error="${OPTARG:-}";;
		no_info_wrap ) arg_no_info_wrap="${OPTARG:-}";;
		no_summary ) arg_no_summary="${OPTARG:-}";;
		no_colors ) arg_no_colors="${OPTARG:-}";;

		value ) arg_value="${OPTARG:-}";;
		path ) arg_path="${OPTARG:-}";;
		date_format ) arg_date_format="${OPTARG:-}";;
		time_format ) arg_time_format="${OPTARG:-}";;
		datetime_format ) arg_datetime_format="${OPTARG:-}";;

		src_file ) arg_src_file="${OPTARG:-}";;
		dest_dir ) arg_dest_dir="${OPTARG:-}";;
		file_extension ) arg_file_extension="${OPTARG:-}";;
		remove_empty_values ) arg_remove_empty_values="${OPTARG:-}";;

		??* ) ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"util:error")
		if [ "${arg_no_error:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_error:-}"
			[ "${arg_no_colors:-}" != "true" ] && msg="${RED}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		exit 2
		;;
	"util:warn")
		if [ "${arg_no_warn:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_warn:-}"
			[ "${arg_no_colors:-}" != "true" ] && msg="${YELLOW}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info")
		if [ "${arg_no_info:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_info:-}"
			[ "${arg_no_colors:-}" != "true" ] && msg="${GRAY}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:start")
		if [ "${arg_no_info_wrap:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_title:-} - start"
			[ "${arg_no_colors:-}" != "true" ] && msg="${CYAN}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:end")
		if [ "${arg_no_info_wrap:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_title:-} - end"
			[ "${arg_no_colors:-}" != "true" ] && msg="${CYAN}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:summary")
		if [ "${arg_no_summary:-}" != "true" ]; then
			msg="[summary] ${arg_title:-}: ${arg_start:-} - ${arg_end:-}"
			[ "${arg_no_colors:-}" != "true" ] &&  msg="${PURPLE}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:urlencode")
		# shellcheck disable=SC2016
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" jq -nr --arg v "${arg_value:-}" '$v|@uri'
		;;
	"util:values_to_files")
		if [ -z "${arg_src_file:-}" ]; then
			error "$title: src_file not specified"
		fi

		if [ -z "${arg_dest_dir:-}" ]; then
			error "$title: dest_dir not specified"
		fi

		if [ ! -f "${arg_src_file:-}" ]; then
			error "$title: src file not found (${arg_src_file:-})"
		fi

		if [ ! -d "$arg_dest_dir" ]; then
			mkdir -p "$arg_dest_dir"
		fi

		while IFS='=' read -r key value; do
			trimmed_key="$(echo "$key" | xargs)"

			if [[ ! "$trimmed_key" == \#* ]]; then
				if [[ "$trimmed_key" = */* ]]; then
					error "$title: invalid file name (key): $trimmed_key"
				fi

				dest_file="${arg_dest_dir}/${trimmed_key}${arg_file_extension:-}"

				if [ -z "$(echo "$value" | xargs)" ] && [ "${arg_remove_empty_values:-}" = 'true' ]; then
					if [ -f "${dest_file:-}" ]; then
						rm "${dest_file:-}"
					fi
				else
					umask u=rwx,g=,o=
					echo -e "$(echo "$value" | xargs)" > "${dest_file:-}"
				fi
			fi
		done < "$arg_src_file"
		;;
	"util:file:type")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			"$inner_run_file" "inner:util:file:type" ${args[@]+"${args[@]}"}
		;;
	"inner:util:file:type")
		if [ -f "${arg_path:-}" ]; then
			echo "file"
		elif [ -d "${arg_path:-}" ]; then
			echo "dir"
		else
			echo "path (${arg_path:-}) not found" >&2
			exit 2
		fi
		;;
	"util:replace_placeholders")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			"$inner_run_file" "inner:util:replace_placeholders" ${args[@]+"${args[@]}"}
		;;
	"inner:util:replace_placeholders")
		inner_str="${arg_value:-}"

		regex_empty="\[\[[ ]*\]\]"

		if [[ "$inner_str" =~ $regex_empty ]]; then
			empty=''
			shopt -s extglob && inner_str="${inner_str//[[][[]*( )[]][]]/$empty}"
		fi

		regex_random="\[\[[ ]*random[ ]*\]\]"

		if [[ "$inner_str" =~ $regex_random ]]; then
			random=$((RANDOM * RANDOM))
			shopt -s extglob && inner_str="${inner_str//[[][[]*( )random*( )[]][]]/$random}"
		fi

		regex_date="\[\[[ ]*date[ ]*\]\]"
		date_format="${arg_date_format:-}"

		if [[ $inner_str =~ $regex_date ]]; then
			default_date_format='%Y%m%d'
			date="$(date "+${date_format:-$default_date_format}")"
			shopt -s extglob && inner_str="${inner_str//[[][[]*( )date*( )[]][]]/$date}"
		fi

		regex_time="\[\[[ ]*time[ ]*\]\]"
		time_format="${arg_time_format:-}"

		if [[ $inner_str =~ $regex_time ]]; then
			default_time_format='%H%M%S'
			time="$(date "+${time_format:-$default_time_format}")"
			shopt -s extglob && inner_str="${inner_str//[[][[]*( )time*( )[]][]]/$time}"
		fi

		regex_datetime="\[\[[ ]*datetime[ ]*\]\]"
		datetime_format="${arg_datetime_format:-}"

		if [[ $inner_str =~ $regex_datetime ]]; then
			default_datetime_format='%Y%m%d.%H%M%S'
			datetime="$(date "+${datetime_format:-$default_datetime_format}")"
			shopt -s extglob && inner_str="${inner_str//[[][[]*( )datetime*( )[]][]]/$datetime}"
		fi

		echo "$inner_str"
		;;
	*)
		error "$command: invalid command"
		;;
esac
