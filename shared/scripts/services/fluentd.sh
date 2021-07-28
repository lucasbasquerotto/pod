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
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

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
		fluentd_service ) arg_fluentd_service="${OPTARG:-}";;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"service:fluentd:reload")
		>&2 "$pod_script_env_file" kill -s USR2 "$arg_fluentd_service"
		;;
	*)
		error "$command: invalid command"
		;;
esac
