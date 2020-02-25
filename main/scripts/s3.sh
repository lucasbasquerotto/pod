#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

RED='\033[0;31m'
NC='\033[0m' # No Color

command="${1:-}"

if [ -z "$command" ]; then
	echo -e "${RED}No command entered (db).${NC}"
	exit 1
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
		echo -e "${RED}Invalid command: $command ${NC}"
		exit 1
    ;;
esac