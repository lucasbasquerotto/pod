#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
pod_data_dir="$var_pod_data_dir"
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
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		webservice ) arg_webservice="${OPTARG:-}";;
		output_file_format ) arg_output_file_format="${OPTARG:-}";;
		output_file_relpath ) arg_output_file_relpath="${OPTARG:-}";;
		only_if_needed )
			arg_only_if_needed="${OPTARG:-}";
			[ -z "${OPTARG:-}" ] && arg_only_if_needed='true'
			;;
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
		output_file_outer="/var/main/data/${arg_output_file_relpath:-}"

		tmp_dir_inner='/tmp/main/cloudflare'
		reload_file_inner="$tmp_dir_inner/reload"
		reload_file_outer="$pod_data_dir/tmp/cloudflare/reload"

		if [ ! -f "$output_file_outer" ] || [ "${arg_only_if_needed:-}" != 'true' ]; then
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:service:cloudflare:ips" ${args[@]+"${args[@]}"}

			if [ -f "$reload_file_outer" ] && [ -n "${arg_webservice:-}" ]; then
				echo "reloading $arg_webservice..." >&2
				"$pod_script_env_file" "service:${arg_webservice:-}:reload"
				"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
					rm "$reload_file_inner"
			fi
		fi
		;;
	"inner:service:cloudflare:ips")
		output_file_outer="/var/main/data/${arg_output_file_relpath:-}"
		output_file_inner="/var/main/data/${arg_output_file_relpath:-}"

		tmp_dir_inner='/tmp/main/cloudflare'
		reload_file_inner="$tmp_dir_inner/reload"

		if [ -z "${arg_output_file_relpath:-}" ]; then
			error "$command: output_file_relpath not defined"
		fi

		if [ -z "${arg_output_file_format:-}" ]; then
			error "$command: output_file_format not defined"
		elif [ "${arg_output_file_format:-}" != 'nginx' ] && [ "${arg_output_file_format:-}" != 'haproxy' ]; then
			error "$command: output_file_format invalid"
		fi

		if [ ! -f "$output_file_outer" ] || [ "${arg_only_if_needed:-}" != 'true' ]; then
			mkdir -p "$tmp_dir_inner"
			wget https://www.cloudflare.com/ips-v4 -O "$tmp_dir_inner"/ips-v4.txt >&2
			wget https://www.cloudflare.com/ips-v6 -O "$tmp_dir_inner"/ips-v6.txt >&2
			cat "$tmp_dir_inner"/ips-v4.txt "$tmp_dir_inner"/ips-v6.txt > "$tmp_dir_inner"/ips.txt

			echo "ip rules..." >&2

			if [ "${arg_output_file_format:-}" = 'nginx' ]; then
				sed 's/$/ 1;/' "$tmp_dir_inner"/ips.txt > "$tmp_dir_inner"/ips-rules.txt
			elif [ "${arg_output_file_format:-}" = 'haproxy' ]; then
				cp "$tmp_dir_inner"/ips.txt "$tmp_dir_inner"/ips-rules.txt
			fi

			touch "$output_file_inner"

			checksum1="$(md5sum "$output_file_inner" | awk '{print $1}')"
			checksum2="$(md5sum "$tmp_dir_inner"/ips-rules.txt | awk '{print $1}')"

			if [ "$checksum1" = "$checksum2" ]; then
				echo "rules unchanged - skipping..." >&2
			else
				echo "rules changed - generate final file..." >&2
				mkdir -p "$(dirname "$output_file_inner")"
				cp "$tmp_dir_inner"/ips-rules.txt "$output_file_inner"

				if [ -n "${arg_webservice:-}" ]; then
					touch "$reload_file_inner"
					chmod 666 "$reload_file_inner"
				fi
			fi
		fi
		;;
	*)
		error "$command: invalid command"
		;;
esac
