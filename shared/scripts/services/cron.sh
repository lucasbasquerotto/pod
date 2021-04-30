#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"	   # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"	  # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		cron_src ) cron_src="${OPTARG:-}";;
		cron_dest ) cron_dest="${OPTARG:-}";;
		cron_tmp_dir ) cron_tmp_dir="${OPTARG:-}";;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

if [ -z "${cron_src:-}" ]; then
	error "cron src not specified"
elif [ -z "${cron_dest:-}" ]; then
	error "cron dest not specified"
elif [ -z "${cron_tmp_dir:-}" ]; then
	error "cron temporary directory not specified"
elif [ ! -f "${cron_src:-}" ]; then
	error "cron src file not found (${cron_src:-})"
elif [ -d "${cron_dest:-}" ]; then
	error "the cron destination (${cron_dest:-}) should be a file, but is a directory"
elif [ -f "${cron_tmp_dir:-}" ]; then
	error "the cron temporary directory (${cron_tmp_dir:-}) should be a directory, but is a file"
fi

cron_dest_dir="$(dirname "$cron_dest")"

if [ ! -d "$cron_dest_dir" ]; then
	mkdir -p "$cron_dest_dir"
fi

if [ ! -d "$cron_tmp_dir" ]; then
	mkdir -p "$cron_tmp_dir"
fi

if [ ! -f "$cron_dest" ]; then
	cp "$cron_src" "$cron_dest"
else
	tmp_old="$cron_tmp_dir/old.tmp.cron"
	tmp_new="$cron_tmp_dir/new.tmp.cron"

	sed '/^#/d' < "$cron_dest" > "$tmp_old"
	sed '/^#/d' < "$cron_src" > "$tmp_new"

	sum_old="$(md5sum "$tmp_old" | awk '{ print $1 }')"
	sum_new="$(md5sum "$tmp_new" | awk '{ print $1 }')"

	if [ "$sum_old" != "$sum_new" ]; then
		echo "copying $cron_src to $cron_dest..."
		cp "$cron_src" "$cron_dest"
	else
		echo "skipping (same cron content)..."
	fi
fi

crontab "$cron_dest"
