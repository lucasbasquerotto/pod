#!/bin/bash
set -eou pipefail

. "${DIR}/vars.sh"

pod_layer_dir="$DIR"

command="${1:-}"

CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
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