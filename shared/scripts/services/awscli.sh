#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_layer_dir="$var_pod_layer_dir"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
inner_run_file="$var_inner_scripts_dir/run"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

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
		s3_tmp_dir ) arg_s3_tmp_dir="${OPTARG:-}";;
		s3_alias ) arg_s3_alias="${OPTARG:-}";;
		s3_endpoint ) arg_s3_endpoint="${OPTARG:-}";;
		s3_bucket_name ) arg_s3_bucket_name="${OPTARG:-}";;
		s3_lifecycle_dir ) arg_s3_lifecycle_dir="${OPTARG:-}";;
		s3_lifecycle_file ) arg_s3_lifecycle_file="${OPTARG:-}";;
		s3_acl ) arg_s3_acl="${OPTARG:-}";;
		s3_remote_src ) arg_s3_remote_src="${OPTARG:-}" ;;
		s3_src_alias ) ;;
		s3_src ) arg_s3_src="${OPTARG:-}" ;;
		s3_remote_dest ) arg_s3_remote_dest="${OPTARG:-}" ;;
		s3_dest_alias ) ;;
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
	"s3:main:awscli:exec:"*)
		cmd="${command#s3:main:awscli:exec:}"
		"$pod_script_env_file" "s3:main:awscli:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:main:awscli:run:"*)
		cmd="${command#s3:main:awscli:run:}"
		"$pod_script_env_file" "s3:main:awscli:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:awscli:create_bucket")
		bucket_exists="$("$pod_script_env_file" "s3:main:awscli:bucket_exists" ${args[@]+"${args[@]}"})"

		if [ "$bucket_exists" = 'false' ]; then
			info "$command - create bucket"
			inner_cmd=( aws --profile="$arg_s3_alias" )
			inner_cmd+=( s3api --endpoint="$arg_s3_endpoint" )
			inner_cmd+=( create-bucket --bucket "$arg_s3_bucket_name" )

			if [ -n "${arg_s3_acl:-}" ]; then
				inner_cmd+=( --acl "${arg_s3_acl:-}" )
			fi

			inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

			info "s3 command: ${inner_cmd[*]}"

			"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		elif [ "$bucket_exists" != 'true' ]; then
			error "$title: invalid result (bucket_exists should be true or false): $bucket_exists"
		fi
		;;
	"s3:main:awscli:acl")
		if [ -z "${arg_s3_acl:-}" ]; then
			error "$title: parameter s3_acl undefined"
		fi

		inner_cmd=( aws --profile="$arg_s3_alias" )
		inner_cmd+=( s3api --endpoint="$arg_s3_endpoint" )
		inner_cmd+=( put-bucket-acl )
		inner_cmd+=( --bucket "$arg_s3_bucket_name" )
		inner_cmd+=( --acl "${arg_s3_acl:-}" )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:awscli:bucket_exists")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" \
			"$inner_run_file" "inner:service:awscli:bucket_exists" ${args[@]+"${args[@]}"}
		;;
	"inner:service:awscli:bucket_exists")
		mkdir -p "$arg_s3_tmp_dir" >&2

		error_filename="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log" >&2
		error_log_file="$arg_s3_tmp_dir/$error_filename" >&2

		if ! aws s3 --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
				ls "s3://$arg_s3_bucket_name" 1>&2 2> "$error_log_file"; then
			if grep -q 'NoSuchBucket' "$error_log_file" >&2; then
				echo 'false'
				exit 0
			else
				cat "$error_log_file" >&2
				exit 2
			fi
		fi

		echo 'true'
		;;
	"s3:main:awscli:rb")
		bucket_exists="$("$pod_script_env_file" "s3:main:awscli:bucket_exists" ${args[@]+"${args[@]}"})"

		if [ "$bucket_exists" = 'false' ]; then
			>&2 echo "skipping (no_bucket)"
		elif [ "$bucket_exists" = 'true' ]; then
			inner_cmd=( aws --profile="$arg_s3_alias" )
			inner_cmd+=( s3 --endpoint="$arg_s3_endpoint" )
			inner_cmd+=( rb --force "s3://$arg_s3_bucket_name" )
			inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

			info "s3 command: ${inner_cmd[*]}"

			"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		else
			error "$title: invalid result (bucket_exists should be true or false): $bucket_exists"
		fi
		;;
	"s3:main:awscli:delete_old")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" \
			"$inner_run_file" "inner:service:awscli:delete_old" ${args[@]+"${args[@]}"}
		;;
	"inner:service:awscli:delete_old")
		if [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		s3_max_date=''

		if [ -n "${arg_s3_older_than_days:-}" ]; then
			seconds=$(( ${arg_s3_older_than_days:-}*24*60*60 ))
			[ "${arg_s3_test:-}" = 'true' ] && seconds=$(( ${arg_s3_older_than_days:-}*60 ))
			s3_max_date="$(date --date=@"$(( $(date '+%s') - $seconds ))" -Iseconds)"
		fi

		aws --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
			s3api list-objects --bucket "$arg_s3_bucket_name" \
			--query "Contents[?LastModified<='$s3_max_date'].[Key]" \
			--prefix "${arg_s3_path:-}" \
			--output text \
			| { grep -v None ||:; } \
			| xargs --no-run-if-empty -I {} \
				aws --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
					s3 rm s3://"$arg_s3_bucket_name"/{}
		;;
	"s3:main:awscli:cp"|"s3:main:awscli:sync")
		[ "${arg_s3_remote_src:-}" = 'true' ] && s3_src="s3://$arg_s3_src" || s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = 'true' ] && s3_dest="s3://$arg_s3_dest" || s3_dest="$arg_s3_dest"

		cmd="${command#s3:main:awscli:}"

		inner_cmd=( aws --profile="$arg_s3_alias" )
		inner_cmd+=( s3 --endpoint="$arg_s3_endpoint" )
		inner_cmd+=( "$cmd" )

		if [ "$cmd" = 'sync' ]; then
			inner_cmd+=( --no-follow-symlink )
		fi

		inner_cmd+=( "$s3_src" "$s3_dest" )

		if [ -n "${arg_s3_file:-}" ]; then
			inner_cmd+=( --exclude "*" --include "$arg_s3_file" )
		elif [ -n "${arg_s3_ignore_path:-}" ]; then
			inner_cmd+=( --exclude "${arg_s3_ignore_path:-}" )
		fi

		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:awscli:lifecycle")
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

		inner_conf_file="/etc/main/${arg_s3_lifecycle_file:-}"

		inner_cmd=( aws --profile="$arg_s3_alias" )
		inner_cmd+=( s3api --endpoint="$arg_s3_endpoint" )
		inner_cmd+=( put-bucket-lifecycle-configuration )
		inner_cmd+=( --bucket "$arg_s3_bucket_name" )
		inner_cmd+=( --lifecycle-configuration "file://$inner_conf_file" )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:awscli:cmd")
		inner_cmd=( aws --profile="$arg_s3_alias" )
		inner_cmd+=( --endpoint="$arg_s3_endpoint" )
		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	*)
		error "Invalid command: $command"
		;;
esac