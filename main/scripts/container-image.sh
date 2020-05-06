#!/bin/bash
# shellcheck disable=SC2034,SC2153,SC2214
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
	error "No command entered (db)."
fi

shift;

args=("$@")

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		toolbox_service ) arg_toolbox_service="${OPTARG:-}" ;;
		container_type ) arg_container_type="${OPTARG:-}" ;;		
		registry_api_base_url ) arg_registry_api_base_url="${OPTARG:-}" ;;
		registry_host ) arg_registry_host="${OPTARG:-}" ;;
		registry_port ) arg_registry_port="${OPTARG:-}" ;;
		repository ) arg_repository="${OPTARG:-}" ;;
		version ) arg_version="${OPTARG:-}" ;;
		username ) arg_username="${OPTARG:-}" ;;
		pass ) arg_pass="${OPTARG:-}" ;;
		local_image ) arg_local_image="${OPTARG:-}" ;;
		remote_tag ) arg_remote_tag="${OPTARG:-}" ;;
		full_image_name ) arg_full_image_name="${OPTARG:-}" ;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"container:image:tag:exists")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail
			
			>&2 token="$(curl -s -H "Content-Type: application/json" -X POST \
				-d '{"username": "'"${arg_username}"'", "password": "'"${arg_pass}"'"}' \
				"${arg_registry_api_base_url}/users/login/" | jq -r .token)"

			>&2 exists="$(curl -s -H "Authorization: JWT \${token}" \
				"${arg_registry_api_base_url}/repositories/${arg_repository}/tags/?page_size=10000" | \
				jq -r "[.results | .[] | .name == \"${arg_version}\"] | any")"

			if [ "\$exists" = "true" ]; then
				echo "true"
			else 
				echo "false"
			fi
		SHELL
		;;
	"container:image:push")
		full_image_name="$arg_registry_host:$arg_registry_port"
		full_image_name="$full_image_name/$arg_repository:$arg_remote_tag"
		>&2 "$pod_script_env_file" "container:image:push:$arg_container_type" \
			 --local_image="$arg_local_image" \
			 --full_image_name="$full_image_name"
		;;
	"container:image:push:"*)
		cmd="${command#container:image:push:}"
		>&2 "$cmd" tag "$arg_local_image" "$arg_full_image_name"
		>&2 "$cmd" push "$arg_full_image_name"
		;;
	*)
		error "$command: Invalid command"
		;;
esac