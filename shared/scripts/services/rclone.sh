#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		cli_cmd ) arg_cli_cmd="${OPTARG:-}";;
		s3_service ) arg_s3_service="${OPTARG:-}";;
		s3_alias ) arg_s3_alias="${OPTARG:-}";;
		s3_bucket_name ) arg_s3_bucket_name="${OPTARG:-}";;
		s3_acl ) arg_s3_acl="${OPTARG:-}";;
		s3_remote_src ) arg_s3_remote_src="${OPTARG:-}" ;;
		s3_src_alias ) arg_s3_src_alias="${OPTARG:-}" ;;
		s3_src ) arg_s3_src="${OPTARG:-}" ;;
		s3_remote_dest ) arg_s3_remote_dest="${OPTARG:-}" ;;
		s3_dest_alias ) arg_s3_dest_alias="${OPTARG:-}" ;;
		s3_dest ) arg_s3_dest="${OPTARG:-}";;
		s3_path ) arg_s3_path="${OPTARG:-}";;
		s3_file ) arg_s3_file="${OPTARG:-}";;
		s3_older_than_days ) arg_s3_older_than_days="${OPTARG:-}";;
		s3_ignore_path ) arg_s3_ignore_path="${OPTARG:-}";;
		s3_test ) arg_s3_test="${OPTARG:-}";;
		s3_opts ) arg_s3_opts=( "${@:OPTIND}" ); break;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"s3:main:rclone:exec:"*)
		cmd="${command#s3:main:rclone:exec:}"
		"$pod_script_env_file" "s3:main:rclone:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:main:rclone:run:"*)
		cmd="${command#s3:main:rclone:run:}"
		"$pod_script_env_file" "s3:main:rclone:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:rclone:create_bucket")
		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( rclone )
		inner_cmd+=( mkdir )

		if [ -n "${arg_s3_acl:-}" ]; then
			inner_cmd+=( --s3-bucket-acl "${arg_s3_acl:-}" )
		fi

		inner_cmd+=( "$arg_s3_alias:$arg_s3_bucket_name" )

		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:rclone:acl")
		error "$title: action not supported for this s3 client"
		;;
	"s3:main:rclone:rb")
		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( rclone )
		inner_cmd+=( purge "$arg_s3_alias:$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:rclone:delete_old")
		if [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		older_than_unit='d'
		[ "${arg_s3_test:-}" = 'true' ] && older_than_unit='m'
		s3_older_than="${arg_s3_older_than_days:-}$older_than_unit"

		s3_full_path="$arg_s3_alias:$arg_s3_bucket_name/$arg_s3_path"

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( rclone )
		inner_cmd+=( delete --verbose --min-age "$s3_older_than" "$s3_full_path" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:rclone:cp"|"s3:main:rclone:sync")
		[ "${arg_s3_remote_src:-}" = 'true' ] && s3_src="$arg_s3_src_alias:$arg_s3_src" || s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = 'true' ] && s3_dest="$arg_s3_dest_alias:$arg_s3_dest" || s3_dest="$arg_s3_dest"

		params=()

		if [ -n "${arg_s3_file:-}" ]; then
			[[ "$s3_src" = */ ]] && s3_src="${s3_src}${arg_s3_file}" || s3_src="$s3_src/$arg_s3_file"
			[[ "$s3_dest" != */ ]] && s3_dest="$s3_dest/"
		elif [ -n "${arg_s3_ignore_path:-}" ]; then
			exclude="${arg_s3_ignore_path:-}"

			if [[ $exclude = *\* ]] && [[ $exclude != *\*\* ]]; then
				exclude="${exclude}*"
			fi

			params+=( --exclude "$exclude" )
		fi

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( rclone )
		inner_cmd+=( copy --verbose )
		inner_cmd+=( ${params[@]+"${params[@]}"} )
		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )
		inner_cmd+=( "$s3_src" "$s3_dest" )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:rclone:lifecycle")
		error "$title: action not supported for this s3 client"
		;;
	*)
		error "Invalid command: $command"
		;;
esac