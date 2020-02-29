#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
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

args=("$@")

case "$command" in
  "setup:new:wp:db")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    info "$command - installation"
    "$pod_script_run_file" run wordpress \
      wp --allow-root core install \
      --url="$var_setup_url" \
      --title="$var_setup_title" \
      --admin_user="$var_setup_admin_user" \
      --admin_password="$var_setup_admin_password" \
      --admin_email="$var_setup_admin_email"

    if [ ! -z "$var_setup_local_seed_data" ] || [ ! -z "$var_setup_remote_seed_data" ]; then
      info "$command - upgrade..."
      "$pod_script_env_file" upgrade "${args[@]}"

      if [ ! -z "$var_setup_local_seed_data" ]; then
        info "$command - import local seed data"
        "$pod_script_run_file" run wordpress \
          wp --allow-root import ./"$var_setup_local_seed_data" --authors=create
      fi

      if [ ! -z "$var_setup_remote_seed_data" ]; then
        info "$command - import remote seed data"
        "$pod_script_run_file" run wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$var_setup_remote_seed_data' \
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

      info "upgrade (app) - update database"
      wp --allow-root core update-db

      info "upgrade (app) - activate plugins"
      wp --allow-root plugin activate --all

      if [ ! -z "$var_old_domain_host" ] && [ ! -z "$var_new_domain_host" ]; then
        info "upgrade (app) - update domain"
        wp --allow-root search-replace "$var_old_domain_host" "$var_new_domain_host"
      fi
		SHELL
    ;;
  *)
		error "$command: invalid command"
    ;;
esac
