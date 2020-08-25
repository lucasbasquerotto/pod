#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2153
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

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
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

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
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;

		error ) arg_error="${OPTARG:-}";;
		warn ) arg_warn="${OPTARG:-}";;
		info ) arg_info="${OPTARG:-}";;
		cmd ) arg_cmd="${OPTARG:-}";;
		start ) arg_start="${OPTARG:-}";;
		end ) arg_end="${OPTARG:-}";;

		no_info ) arg_no_info="${OPTARG:-}";;
		no_warn ) arg_no_warn="${OPTARG:-}";;
		no_error ) arg_no_error="${OPTARG:-}";;
		no_info_wrap ) arg_no_info_wrap="${OPTARG:-}";;
		no_summary ) arg_no_summary="${OPTARG:-}";;
		no_colors ) arg_no_colors="${OPTARG:-}";;

		value ) arg_value="${OPTARG:-}";;
		date_format ) arg_date_format="${OPTARG:-}";;
		time_format ) arg_time_format="${OPTARG:-}";;
		datetime_format ) arg_datetime_format="${OPTARG:-}";;
		??* ) ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"util:error")
		if [ "${arg_no_error:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_error:-}"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${RED}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		exit 2
		;;
	"util:warn")
		if [ "${arg_no_warn:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_warn:-}"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${YELLOW}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info")
		if [ "${arg_no_info:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_info:-}"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${GRAY}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:start")
		if [ "${arg_no_info_wrap:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_cmd:-} - start"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${CYAN}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:end")
		if [ "${arg_no_info_wrap:-}" != "true" ]; then
			msg="$(date '+%F %T') - ${arg_cmd:-} - end"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${CYAN}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:info:summary")
		if [ "${arg_no_summary:-}" != "true" ]; then
			msg="[summary] ${arg_cmd:-}: ${arg_start:-} - ${arg_end:-}"
			[ "${arg_no_colors:-}" = "true" ] && msg="$msg" || msg="${PURPLE}${msg}${NC}"
			>&2 echo -e "$msg"
		fi
		;;
	"util:urlencode")
		# shellcheck disable=SC2016
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" jq -nr --arg v "${arg_value:-}" '$v|@uri'
		;;
	"util:replace_placeholders")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			inner_srt="${arg_value:-}"

			regex_random="\[\[[ ]*random[ ]*\]\]"

			if [[ "\$inner_srt" =~ \$regex_random ]]; then
				random=\$((RANDOM * RANDOM))
				shopt -s extglob && inner_srt="\${inner_srt//[[][[]*( )random*( )[]][]]/\$random}"
			fi

			regex_date="\[\[[ ]*date[ ]*\]\]"
			backup_date_format="${arg_date_format:-}"

			if [[ \$inner_srt =~ \$regex_date ]]; then
				default_date_format='%Y%m%d'
				date="\$(date "+\${backup_date_format:-\$default_date_format}")"
				shopt -s extglob && inner_srt="\${inner_srt//[[][[]*( )date*( )[]][]]/\$date}"
			fi

			regex_time="\[\[[ ]*time[ ]*\]\]"
			backup_time_format="${arg_time_format:-}"

			if [[ \$inner_srt =~ \$regex_time ]]; then
				default_time_format='%H%M%S'
				time="\$(date "+\${backup_time_format:-\$default_time_format}")"
				shopt -s extglob && inner_srt="\${inner_srt//[[][[]*( )time*( )[]][]]/\$time}"
			fi

			regex_datetime="\[\[[ ]*datetime[ ]*\]\]"
			backup_datetime_format="${arg_datetime_format:-}"

			if [[ \$inner_srt =~ \$regex_datetime ]]; then
				default_datetime_format='%Y%m%d.%H%M%S'
				datetime="\$(date "+\${backup_datetime_format:-\$default_datetime_format}")"
				shopt -s extglob && inner_srt="\${inner_srt//[[][[]*( )datetime*( )[]][]]/\$datetime}"
			fi

			echo "\$inner_srt"
		SHELL
		;;
	*)
		error "$command: invalid command"
		;;
esac
