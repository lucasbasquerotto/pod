#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

function error {
	msg="$(date '+%F %X') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

RED='\033[0;31m'
NC='\033[0m' # No Color

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (db)."
fi

shift;

case "$command" in
	"s3:cp:awscli")
    aws s3 cp --endpoint="$s3_endpoint" "$src" "$dest"
		;;
  "s3:cp:s3cmd")
		s3cmd cp "$src" "$dest"
		;;
  "s3:sync:awscli")
    aws s3 sync --endpoint="$s3_endpoint" "$src" "$dest"
		;;
  "s3:sync:s3cmd")
		s3cmd sync "$src" "$dest"
    ;;
  *)
		error "Invalid command: $command"
    ;;
esac