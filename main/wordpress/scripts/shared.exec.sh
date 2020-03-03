#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_file="$pod_layer_dir/main/compose/main.sh"

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
  error "No command entered (env - shared)."
fi

shift;

args=( "$@" )

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
    setup_url ) setup_url="${OPTARG:-}";;
    setup_title ) setup_title="${OPTARG:-}";;
    setup_admin_user ) setup_admin_user="${OPTARG:-}";;
    setup_admin_password ) setup_admin_password="${OPTARG:-}";;
    setup_admin_email ) setup_admin_email="${OPTARG:-}";;
    setup_local_seed_data ) setup_local_seed_data="${OPTARG:-}";;
    setup_remote_seed_data ) setup_remote_seed_data="${OPTARG:-}";;
		old_domain_host ) old_domain_host="${OPTARG:-}";;
		new_domain_host ) new_domain_host="${OPTARG:-}";; 
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
  "setup:new:wp:db")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    info "$command - installation"
    "$pod_script_run_file" run wordpress \
      wp --allow-root core install \
      --url="$setup_url" \
      --title="$setup_title" \
      --admin_user="$setup_admin_user" \
      --admin_password="$setup_admin_password" \
      --admin_email="$setup_admin_email"

    if [ -n "$setup_local_seed_data" ] || [ -n "$setup_remote_seed_data" ]; then
      info "$command - upgrade..."
      "$pod_script_env_file" upgrade "${args[@]}"

      if [ -n "$setup_local_seed_data" ]; then
        info "$command - import local seed data"
        "$pod_script_run_file" run wordpress \
          wp --allow-root import ./"$setup_local_seed_data" --authors=create
      fi

      if [ -n "$setup_remote_seed_data" ]; then
        info "$command - import remote seed data"
        "$pod_script_run_file" run wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$setup_remote_seed_data' \
          && wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
          && rm -f ./tmp/tmp-seed-data.xml"
      fi
    fi
    ;;
  "upgrade")
    info "upgrade (app) - start container"
    "$pod_script_run_file" up wordpress

    "$pod_script_run_file" exec-nontty wordpress /bin/bash <<-SHELL
			set -eou pipefail

      function info {
        msg="\$(date '+%F %T') - \${1:-}"
        >&2 echo -e "${GRAY}\${msg}${NC}"
      }

      info "upgrade (app) - update database"
      wp --allow-root core update-db

      info "upgrade (app) - activate plugins"
      wp --allow-root plugin activate --all

      if [ -n "${old_domain_host:-}" ] && [ -n "${new_domain_host:-}" ]; then
        info "upgrade (app) - update domain"
        wp --allow-root search-replace "$old_domain_host" "$new_domain_host"
      fi
		SHELL
    ;;
  *)
		error "$command: invalid command"
    ;;
esac
