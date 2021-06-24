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
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

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
		nextcloud_service ) arg_nextcloud_service="${OPTARG:-}";;
		connect_wait_secs ) arg_connect_wait_secs="${OPTARG:-}";;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}";;

		admin_user ) arg_admin_user="${OPTARG:-}";;
		admin_pass ) arg_admin_pass="${OPTARG:-}";;
		nextcloud_url ) arg_nextcloud_url="${OPTARG:-}";;
		nextcloud_domain ) arg_nextcloud_domain="${OPTARG:-}";;
		nextcloud_host ) arg_nextcloud_host="${OPTARG:-}";;
		nextcloud_protocol ) arg_nextcloud_protocol="${OPTARG:-}";;

		mount_point ) arg_mount_point="${OPTARG:-}";;

		datadir ) arg_datadir="${OPTARG:-}";;

		bucket ) arg_bucket="${OPTARG:-}";;
		hostname ) arg_hostname="${OPTARG:-}";;
		port ) arg_port="${OPTARG:-}";;
		region ) arg_region="${OPTARG:-}";;
		use_ssl ) arg_use_ssl="${OPTARG:-}";;
		use_path_style ) arg_use_path_style="${OPTARG:-}";;
		legacy_auth ) arg_legacy_auth="${OPTARG:-}";;
		key ) arg_key="${OPTARG:-}";;
		secret ) arg_secret="${OPTARG:-}";;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"service:nextcloud:setup")
		"$pod_script_env_file" up "$arg_nextcloud_service"
		connect_wait_secs="${arg_connect_wait_secs:-300}"

		need_install="$(
			"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
				bash "$inner_run_file" "inner:service:nextcloud:setup:need_install" ${args[@]+"${args[@]}"} \
		)" || error "inner:service:nextcloud:setup:need_install"

		if [[ ${need_install:-0} -ne 0 ]]; then
			info "$command: installing nextcloud..."
			"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
				php occ maintenance:install \
				--admin-user="$arg_admin_user" \
				--admin-pass="$arg_admin_pass"
		else
			info "$command: nextcloud already installed"
		fi

		info "$command: define domain and protocol ($arg_nextcloud_domain)"
		"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
			bash "$inner_run_file" "inner:service:nextcloud:setup:main" ${args[@]+"${args[@]}"}
		;;
	"inner:service:nextcloud:setup:need_install")
		connect_wait_secs="${arg_connect_wait_secs:-300}"
		end=$((SECONDS+connect_wait_secs))
		result="continue"

		while [ -n "${result:-}" ] && [ $SECONDS -lt $end ]; do
			current=$((end-SECONDS))
			msg="$connect_wait_secs seconds - $current second(s) remaining"

			>&2 echo "wait for the installation to be ready ($msg)"
			result="$(php occ list > /dev/null 2>&1 || echo "continue")"

			if [ -n "${result:-}" ]; then
				sleep "${arg_connection_sleep:-5}"
			fi
		done

		php occ list | grep -c '^ *maintenance:install ' ||:
		;;
	"inner:service:nextcloud:setup:main")
		php occ config:system:set trusted_domains 1 --value="$arg_nextcloud_domain"
		php occ config:system:set overwrite.cli.url --value="$arg_nextcloud_url"
		php occ config:system:set overwritehost --value="$arg_nextcloud_host"
		php occ config:system:set overwriteprotocol --value="$arg_nextcloud_protocol"

		mime_src="/tmp/main/config/mimetypemapping.json"
		mime_dest="/var/www/html/config/mimetypemapping.json"

		if [ -f "$mime_src" ] && [ ! -f "$mime_dest" ]; then
			>&2 echo "$title: copy mimetypemapping.json"
			cp "$mime_src" "$mime_dest"
		fi
		;;
	"service:nextcloud:fs")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_nextcloud_service"

		info "$command: nextcloud enable files_external"
		"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
			php occ app:enable files_external

		info "$command - verify defined mounts"
		list="$("$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
			php occ files_external:list --output=json)" || error "service:nextcloud:fs - list"

		info "$command - count defined mounts with the mount point equal to $arg_mount_point"
		count="$(
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash \
				<<-'SHELL' -s "$list" "$arg_mount_point"
					set -eou pipefail
					echo "$1" | jq '[.[] | select(.mount_point == "'"$2"'")] | length'
				SHELL
		)" || error "service:nextcloud:fs - count"

		if [[ $count -eq 0 ]]; then
			info "$command: defining fs storage ($arg_mount_point)..."
			"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
				php occ files_external:create "$arg_mount_point" \
				local --config datadir="${arg_datadir}" "null::null"
		else
			info "$command: fs storage already defined ($arg_mount_point)"
		fi
		;;
	"service:nextcloud:s3")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_nextcloud_service"

		info "$command: nextcloud enable files_external"
		"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
			php occ app:enable files_external

		info "$command - verify defined mounts"
		list="$("$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
			php occ files_external:list --output=json)" || error "service:nextcloud:s3 - list"

		info "$command - count defined mounts with the mount point equal to $arg_mount_point"
		count="$(
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash \
				<<-'SHELL' -s "$list" "$arg_mount_point"
					set -eou pipefail
					echo "$1" | jq '[.[] | select(.mount_point == "'"$2"'")] | length'
				SHELL
		)" || error "service:nextcloud:s3 - count"

		if [[ $count -eq 0 ]]; then
			info "$command: defining s3 storage ($arg_mount_point)..."
			"$pod_script_env_file" exec-nontty -u www-data "$arg_nextcloud_service" \
				bash "$inner_run_file" "inner:service:nextcloud:s3" ${args[@]+"${args[@]}"}
		else
			info "$command: s3 storage already defined ($arg_mount_point)"
		fi
		;;
	"inner:service:nextcloud:s3")
		php occ files_external:create "$arg_mount_point" \
			amazons3 \
				--config bucket="${arg_bucket}" \
				--config hostname="${arg_hostname:-}" \
				--config port="${arg_port:-}" \
				--config region="${arg_region:-}" \
				--config use_ssl="${arg_use_ssl:-}" \
				--config use_path_style="${arg_use_path_style:-}" \
				--config legacy_auth="${arg_legacy_auth:-}"  \
			amazons3::accesskey \
				--config key="$arg_key" \
				--config secret="$arg_secret"
		;;
	*)
		error "$title: invalid title"
		;;
esac