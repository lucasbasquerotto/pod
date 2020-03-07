#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"

. "${pod_vars_dir}/vars.sh"

pod_env_shared_exec_file="$pod_layer_dir/main/wordpress/scripts/shared.exec.sh"

pod_script_run_vars_file="$pod_layer_dir/main/vars/main.sh"

RED='\033[0;31m'
NC='\033[0m' # No Color

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
	"upgrade")
    opts=()

    opts+=( "--setup_url=$var_upgrade_url" )
    opts+=( "--setup_title=$var_upgrade_title" )
    opts+=( "--setup_admin_user=$var_upgrade_admin_user" )
    opts+=( "--setup_admin_password=$var_upgrade_admin_password" )
    opts+=( "--setup_admin_email=$var_upgrade_admin_email" )
    opts+=( "--setup_restore_seed=${var_upgrade_restore_seed:-}" )
    opts+=( "--setup_local_seed_data=${var_upgrade_local_seed_data:-}" )
    opts+=( "--setup_remote_seed_data=${var_upgrade_remote_seed_data:-}" )
    opts+=( "--old_domain_host=${var_upgrade_old_domain_host:-}" )
    opts+=( "--new_domain_host=${var_upgrade_new_domain_host:-}" )

    "$pod_env_shared_exec_file" upgrade "${opts[@]}"
    ;;
  "setup:new:wp:db")
    "$pod_env_shared_exec_file" "setup:new:wp:db" ${args[@]+"${args[@]}"}
    ;;
  *)
		"$pod_script_run_vars_file" "$command" ${args[@]+"${args[@]}"}
    ;;
esac
