#!/bin/bash
# shellcheck disable=SC1090,SC2154
set -eou pipefail

. "${pod_vars_dir}/vars.sh"

command="${1:-}"

CYAN='\033[0;36m'
NC='\033[0m' # No Color

start="$(date '+%F %X')"
echo -e "${CYAN}$(date '+%F %X') - env - $command - start${NC}"

case "$command" in
    *)
        echo -e "env - $command - nothing to run"
        ;;
esac

echo -e "${CYAN}$(date '+%F %X') - env - $command - end${NC}"
end="$(date '+%F %X')"
echo -e "${CYAN}env - $command - $start - $end${NC}"