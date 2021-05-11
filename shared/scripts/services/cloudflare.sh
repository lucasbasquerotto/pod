#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
pod_data_dir="$var_pod_data_dir"

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
		webservice ) arg_webservice="${OPTARG:-}";;
		output_file ) arg_output_file="${OPTARG:-}";;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"service:cloudflare:ips")
		tmp_dir_inner='/tmp/main/cloudflare'
		reload_file_inner="$tmp_dir_inner/reload"
		reload_file_outer="$pod_data_dir/tmp/cloudflare/reload"

		if [ -z "${arg_webservice:-}" ]; then
			error "$command: webservice not defined"
		fi

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			mkdir -p "$tmp_dir_inner"
			wget https://www.cloudflare.com/ips-v4 -O "$tmp_dir_inner"/ips-v4.txt >&2
			wget https://www.cloudflare.com/ips-v6 -O "$tmp_dir_inner"/ips-v6.txt >&2
			cat "$tmp_dir_inner"/ips-v4.txt "$tmp_dir_inner"/ips-v6.txt > "$tmp_dir_inner"/ips.txt

			echo "ip rules..." >&2
			sed 's/$/ 1;/' "$tmp_dir_inner"/ips.txt > "$tmp_dir_inner"/ips-rules.txt

			touch "$arg_output_file"

			checksum1="$(md5sum "$arg_output_file" | awk '{print $1}')"
			checksum2="$(md5sum "$tmp_dir_inner"/ips-rules.txt | awk '{print $1}')"

			if [ "\$checksum1" = "\$checksum2" ]; then
				echo "rules unchanged - skipping..." >&2
			else
				echo "rules changed - generate final file..." >&2
				mkdir -p "$(basedir "$arg_output_file")"
				cp "$tmp_dir_inner"/ips-rules.txt "$arg_output_file"
				touch "$reload_file_inner"
				chmod 666 "$reload_file_inner"
			fi
		SHELL

		if [ -f "$reload_file_outer" ]; then
			echo "reloading $arg_webservice..." >&2
			"$pod_script_env_file" "service:${arg_webservice}:reload"
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				rm "$reload_file_inner"
		fi
		;;
	*)
		error "$command: invalid command"
		;;
esac
