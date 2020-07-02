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
		nextcloud_service ) arg_nextcloud_service="${OPTARG:-}";;

		admin_user ) arg_admin_user="${OPTARG:-}";;
		admin_pass ) arg_admin_pass="${OPTARG:-}";;

		mount_point ) arg_mount_point="${OPTARG:-}";;
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

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"nextcloud:setup")
		"$pod_script_env_file" up "$arg_nextcloud_service"

		installed="$(
			"$pod_script_env_file" exec -T -u www-data "$arg_nextcloud_service" /bin/bash <<-'SHELL'
				set -eou pipefail
				php occ list | grep '^ *maintenance:install ' | wc -l || :
			SHELL
		)" || error "nextcloud:setup"

		if [[ ${installed:-0} -ne 0 ]]; then
			info "$title: installing nextcloud..."
			"$pod_script_env_file" exec -T -u www-data "$arg_nextcloud_service" php occ maintenance:install \
				--admin-user="$arg_admin_user" \
				--admin-pass="$arg_admin_pass"
		else
			info "$title: nextcloud already installed"
		fi
		;;
	"nextcloud:s3")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_nextcloud_service"

		info "$title: nextcloud enable files_external"
		"$pod_script_env_file" exec -T -u www-data "$arg_nextcloud_service" php occ app:enable files_external

		list="$("$pod_script_env_file" exec -T -u www-data "$arg_nextcloud_service" \
      php occ files_external:list --output=json)" || error "nextcloud:s3 - list"

		count="$(
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash \
				<<-'SHELL' -s "$list" "$arg_mount_point"
					set -eou pipefail
					echo "$1" | jq '[.[] | select(.mount_point == "'"$2"'")] | length'
				SHELL
		)" || error "nextcloud:s3 - count"

		if [[ $count -eq 0 ]]; then
			info "$title: defining s3 storage ($arg_mount_point)..."
			"$pod_script_env_file" exec -T -u www-data "$arg_nextcloud_service" /bin/bash <<-SHELL
				set -eou pipefail

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
			SHELL
		else
			info "$title: s3 storage already defined ($arg_mount_point)"
		fi
		;;
	*)
		error "$title: invalid title"
		;;
esac