#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

command="${1:-}"

CYAN='\033[0;36m'
NC='\033[0m' # No Color

start="$(date '+%F %X')"

case "$command" in
  "setup"|"backup")
    echo -e "${CYAN}$(date '+%F %X') - env (remote) - $command - start${NC}"
    ;;
esac

case "$command" in
  *)
    "$pod_env_shared_file_full" "$command" "$@"
    ;;
esac

end="$(date '+%F %X')"

case "$command" in
  "setup"|"backup")
    echo -e "${CYAN}$(date '+%F %X') - env (remote) - $command - end${NC}"
    echo -e "${CYAN}env (remote) - $command - $start - $end${NC}"
    ;;
esac