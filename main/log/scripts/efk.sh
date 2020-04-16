#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_layer_dir="$POD_LAYER_DIR"
pod_vars_dir="$POD_VARS_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_main_file="$pod_layer_dir/main/scripts/main.sh"

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
  error "no command entered"
fi

shift;

args=( "$@" )

case "$command" in
  "prepare")
    info "$command - do nothing..."
    ;;
  "migrate")
    "$pod_script_env_file" "migrate:$var_pod_type" ${args[@]+"${args[@]}"}
    ;;
  "migrate:app")
    "$pod_script_env_file" "migrate:fluentd" ${args[@]+"${args[@]}"}
    "$pod_script_env_file" "migrate:es" ${args[@]+"${args[@]}"}
    "$pod_script_env_file" "migrate:kibana" ${args[@]+"${args[@]}"}
    ;;
  "migrate:fluentd")
    info "$command - nothing to do..."
    ;;
  "migrate:es")
    vm_max_map_count="${var_migrate_es_vm_max_map_count:-262144}"
    info "$command increasing vm max map count to $vm_max_map_count"
    sudo sysctl -w vm.max_map_count="$vm_max_map_count"
    ;;
  "migrate:kibana")
    info "$command - nothing to do..."
    ;;
  *)
		"$pod_script_run_main_file" "$command" ${args[@]+"${args[@]}"}
    ;;
esac
