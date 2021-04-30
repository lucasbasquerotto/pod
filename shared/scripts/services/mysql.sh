#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		max_amount ) arg_max_amount="${OPTARG:-}";;
		log_file ) arg_log_file="${OPTARG:-}";;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"service:mysql:log:slow:summary")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			echo -e "##############################################################################################################"
			echo -e "##############################################################################################################"
			echo -e "MySQL - Slow Logs"
			echo -e "--------------------------------------------------------------------------------------------------------------"
			echo -e "Path: $arg_log_file"
			echo -e "Limit: $arg_max_amount"

			if [ -f "$arg_log_file" ]; then
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_qtd_slow_logs="\$( \
					{ grep '^# User@Host' "$arg_log_file" \
					| awk ' \
						{ s[substr(\$3, 0, index(\$3, "["))]+=1 } END \
						{ for (key in s) { printf "%10d %s\n", s[key], key } } \
						' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_qtd_slow_logs"

				echo -e "##############################################################################################################"
    			echo -e "MySQL - Slow Logs - Times with slowest logs per user"
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_slowest_logs_per_user="\$( \
					{ grep -E '^(# Time: |# User@Host: |# Query_time: )' "$arg_log_file" \
					| awk ' \
						{ \
							if (\$2 == "Time:") {time = \$3 " " \$4;} \
							else if (\$2 == "User@Host:") { \
								user = substr(\$3, 0, index(\$3, "[")); \
							} \
							else if (\$2 == "Query_time:") { \
								if (s[user] < \$3) { s[user] = \$3; t[user] = time; } \
							} \
						} END \
						{ for (key in s) { printf "%10.1f %12s %s\n", s[key], key, t[key] } } \
					' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_slowest_logs_per_user"

				echo -e "##############################################################################################################"
    			echo -e "MySQL - Slow Logs - Times with slowest logs"
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_slowest_logs="\$( \
					{ grep -E '^(# Time: |# User@Host: |# Query_time: )' "$arg_log_file" \
					| awk '{ \
						if(\$2 == "Time:") {time = \$3 " " \$4;} \
						else if (\$2 == "User@Host:") { \
							user = substr(\$3, 0, index(\$3, "[")); \
						} \
						else if (\$2 == "Query_time:") { \
							printf "%10.1f %12s %s\n", \$3, user, time \
						} \
					}' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_slowest_logs"
			fi
		SHELL
		;;
	*)
		error "$command: invalid command"
		;;
esac
