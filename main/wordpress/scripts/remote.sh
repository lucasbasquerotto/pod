#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"

. "${pod_vars_dir}/vars.sh"

pod_env_shared_file="$pod_layer_dir/main/wordpress/scripts/shared.sh"

command="${1:-}"

GRAY='\033[0;90m'
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

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

case "$command" in
  "prepare")
    info "$command - do nothing..."
    ;;
  *)
    "$pod_env_shared_file" "$command" "$@"
    ;;
esac