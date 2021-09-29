#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_shared_run_file="$var_pod_layer_dir/shared/scripts/shared.sh"

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

"$pod_shared_run_file" "$@"