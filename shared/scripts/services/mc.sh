#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
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
		s3_lifecycle_dir ) arg_s3_lifecycle_dir="${OPTARG:-}";;
		s3_lifecycle_file ) arg_s3_lifecycle_file="${OPTARG:-}";;
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
	"s3:main:mc:exec:"*)
		cmd="${command#s3:main:mc:exec:}"
		"$pod_script_env_file" "s3:main:mc:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:main:mc:run:"*)
		cmd="${command#s3:main:mc:run:}"
		"$pod_script_env_file" "s3:main:mc:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:mc:create_bucket")
		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( mb --ignore-existing "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"

		if [ -n "${arg_s3_acl:-}" ]; then
			"$pod_script_env_file" "s3:main:mc:acl" ${args[@]+"${args[@]}"}
		fi
		;;
	"s3:main:mc:acl")
		if [ -z "${arg_s3_acl:-}" ]; then
			error "$title: parameter s3_acl undefined"
		fi

		policy='none'

		if [ "${arg_s3_acl:-}" = 'public-read' ]; then
			policy='download'
		elif [ "${arg_s3_acl:-}" = 'public-read-write' ]; then
			policy='public'
		elif [ "${arg_s3_acl:-}" != 'private' ]; then
			error "$title: parameter s3_acl invalid (${arg_s3_acl:-})"
		fi

		policy='none'
		[ "${arg_s3_acl:-}" = 'public-read' ] && policy='download'

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( policy set "$policy" )
		inner_cmd+=( "$arg_s3_alias/$arg_s3_bucket_name/${arg_s3_path:-}" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:rb")
		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( rb --force "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:delete_old")
		if [ -z "${arg_s3_alias:-}" ]; then
			error "$title: parameter s3_alias is undefined"
		elif [ -z "${arg_s3_bucket_name:-}" ]; then
			error "$title: parameter s3_bucket_name is undefined"
		elif [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		s3_full_path="$arg_s3_alias/$arg_s3_bucket_name/$arg_s3_path"

		older_than_unit='d'
		[ "${arg_s3_test:-}" = 'true' ] && older_than_unit='m'
		s3_older_than="${arg_s3_older_than_days:-}$older_than_unit"

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( rm -r --force --older-than "$s3_older_than" "$s3_full_path" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:sync")
		if [ -n "${arg_s3_file:-}" ]; then
			[[ "$arg_s3_src" = */ ]] \
				&& s3_src="${arg_s3_src}${arg_s3_file}" \
				|| s3_src="$arg_s3_src/$arg_s3_file"
			[[ "$arg_s3_dest" = */ ]] \
				&& s3_dest="$arg_s3_dest" \
				|| s3_dest="$arg_s3_dest/"
			"$pod_script_env_file" "s3:main:mc:cp" ${args[@]+"${args[@]}"} \
				--s3_src="$s3_src" --s3_dest="$s3_dest"
		else
			"$pod_script_env_file" "s3:main:mc:mirror" ${args[@]+"${args[@]}"}
		fi
		;;
	"s3:main:mc:cp"|"s3:main:mc:mirror")
		[ "${arg_s3_remote_src:-}" = 'true' ] \
			&& s3_src="$arg_s3_src_alias/$arg_s3_src" \
			|| s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = 'true' ] \
			&& s3_dest="$arg_s3_dest_alias/$arg_s3_dest" \
			|| s3_dest="$arg_s3_dest"

		cmd="${command#s3:main:mc:}"

		params=()

		if [ "$cmd" = 'mirror' ]; then
			params+=( --overwrite )
		fi

		if [ -n "${arg_s3_ignore_path:-}" ]; then
			[[ "$s3_src" = */ ]] \
				&& s3_src_aux="${s3_src}" \
				|| s3_src_aux="$s3_src/"

			s3_ignore_path="${arg_s3_ignore_path:-}"

			if [[ "$s3_ignore_path" == "$s3_src_aux"* ]]; then
				s3_ignore_path=${s3_ignore_path#"$s3_src_aux"}
			fi

			params+=( --exclude "$s3_ignore_path" )
		fi

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( "$cmd" )
		inner_cmd+=( ${params[@]+"${params[@]}"} )
		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )
		inner_cmd+=( "$s3_src" "$s3_dest" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:lifecycle")
		if [ -z "${arg_s3_lifecycle_file:-}" ]; then
			error "$title: parameter s3_lifecycle_file undefined"
		fi

		s3_lifecycle_file_path="${pod_layer_dir}/${arg_s3_lifecycle_file:-}"

		if [ -n "${arg_s3_lifecycle_dir:-}" ]; then
			s3_lifecycle_file_path="${pod_layer_dir}/${arg_s3_lifecycle_dir:-}/${arg_s3_lifecycle_file:-}"
		fi

		if [ ! -f "$s3_lifecycle_file_path" ]; then
			error "$title: s3_lifecycle_file ($s3_lifecycle_file_path) not found"
		fi

		inner_cmd=()
		[ "$arg_cli_cmd" != 'run' ] && inner_cmd+=( mc )
		inner_cmd+=( ilm import "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]} < $s3_lifecycle_file_path"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}" < "$s3_lifecycle_file_path"
		;;
	"s3:main:mc:cmd")
		inner_cmd=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	*)
		error "Invalid command: $command"
		;;
esac