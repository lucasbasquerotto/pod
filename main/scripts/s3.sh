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
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

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
		s3_lifecycle_file ) arg_s3_lifecycle_file="${OPTARG:-}";;
		s3_remote_src ) arg_s3_remote_src="${OPTARG:-}" ;;
		s3_src_alias ) arg_s3_src_alias="${OPTARG:-}" ;;
		s3_src ) arg_s3_src="${OPTARG:-}" ;;
		s3_remote_dest ) arg_s3_remote_dest="${OPTARG:-}" ;;
		s3_dest_alias ) arg_s3_dest_alias="${OPTARG:-}" ;;
		s3_dest ) arg_s3_dest="${OPTARG:-}";;
		s3_path ) arg_s3_path="${OPTARG:-}";;
		s3_older_than_days ) arg_s3_older_than_days="${OPTARG:-}";;
		s3_opts ) arg_s3_opts=( "${@:OPTIND}" ); break;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

function s3cmd_general {
	>&2 "$pod_script_env_file" "$1" "$arg_s3_service" s3cmd "${@:2}"
}

function s3cmd_exec {
	s3cmd_general exec-nontty "${@}"
}

function s3cmd_run {
	s3cmd_general run "${@}"
}

case "$command" in
	"s3:mc:exec:"*)
		cmd="${command#s3:mc:exec:}"
		"$pod_script_env_file" "run:s3:main:mc:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:mc:run:"*)
		cmd="${command#s3:mc:run:}"
		"$pod_script_env_file" "run:s3:main:mc:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:mc:create_bucket")
		inner_cmd=( mb --ignore-existing "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:bucket_exists")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" /bin/sh <<-SHELL
			set -eou pipefail

			mkdir -p "$arg_s3_tmp_dir" >&2

			error_filename="error.\$(date '+%s').\$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log" >&2
			error_log_file="$arg_s3_tmp_dir/\$error_filename" >&2

			if ! mc ls "$arg_s3_alias/$arg_s3_bucket_name" 1>&2 2> "\$error_log_file"; then
				if grep -q 'NoSuchBucket' "\$error_log_file" >&2; then
					echo "false"
					exit 0
				else
					cat "\$error_log_file" >&2
					exit 2
				fi
			fi

			echo "true"
		SHELL
		;;
	"s3:main:mc:rb")
		inner_cmd=( rb --force "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:delete_old")
		if [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		inner_cmd=( rm -r --older-than "${arg_s3_older_than_days:-}" --force "$arg_s3_path" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:sync")
		"$pod_script_env_file" "run:s3:main:mc:mirror" ${args[@]+"${args[@]}"}
		;;
	"s3:main:mc:cp"|"s3:main:mc:mirror")
		[ "${arg_s3_remote_src:-}" = "true" ] \
			&& s3_src="$arg_s3_src_alias/$arg_s3_src" \
			|| s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = "true" ] \
			&& s3_dest="$arg_s3_dest_alias/$arg_s3_dest" \
			|| s3_dest="$arg_s3_dest"

		cmd="${command#s3:main:mc:}"

		params=()

		if [ "$cmd" = 'mirror' ]; then
			params+=( --overwrite )
		fi

		inner_cmd=()
		inner_cmd+=( "$cmd" )
		inner_cmd+=( ${params[@]+"${params[@]}"} )
		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )
		inner_cmd+=( "$s3_src" "$s3_dest" )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:mc:lifecycle")
		conf_file="${pod_layer_dir}/env/mc/etc/${arg_s3_lifecycle_file:-}"

		if [ -z "${arg_s3_lifecycle_file:-}" ]; then
			error "$title: parameter s3_lifecycle_file undefined"
		elif [ ! -f "$conf_file" ]; then
			error "$title: file ($arg_s3_lifecycle_file) s3_lifecycle_file not found"
		fi

		inner_cmd=( ilm import "$arg_s3_alias/$arg_s3_bucket_name" )
		info "s3 command: ${inner_cmd[*]} < $conf_file"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}" < "$conf_file"
		;;
	"s3:main:mc:cmd")
		inner_cmd=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )
		info "s3 command: ${inner_cmd[*]}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:rclone:exec:"*)
		cmd="${command#s3:rclone:exec:}"
		"$pod_script_env_file" "run:s3:main:rclone:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:rclone:run:"*)
		cmd="${command#s3:rclone:run:}"
		"$pod_script_env_file" "run:s3:main:rclone:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:rclone:create_bucket")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" rclone mkdir "$arg_s3_alias:$arg_s3_bucket_name"
		;;
	"s3:main:rclone:rb")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" rclone purge "$arg_s3_alias:$arg_s3_bucket_name"
		;;
	"s3:main:rclone:bucket_exists")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" /bin/sh <<-SHELL
			set -eou pipefail

			mkdir -p "$arg_s3_tmp_dir" >&2

			error_filename="error.\$(date '+%s').\$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log" >&2
			error_log_file="$arg_s3_tmp_dir/\$error_filename" >&2

			if ! mc ls "$arg_s3_alias:$arg_s3_bucket_name" 1>&2 2> "\$error_log_file"; then
				if grep -q 'NoSuchBucket' "\$error_log_file" >&2; then
					echo "false"
					exit 0
				else
					cat "\$error_log_file" >&2
					exit 2
				fi
			fi

			echo "true"
		SHELL
		;;
	"s3:main:rclone:delete_old")
		if [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		>&2 "$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" \
			rclone delete --min-age "${arg_s3_older_than_days:-}d" "$arg_s3_path"
		;;
	"s3:main:rclone:cp"|"s3:main:rclone:sync")
		[ "${arg_s3_remote_src:-}" = "true" ] && s3_src="$arg_s3_src_alias:$arg_s3_src" || s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = "true" ] && s3_dest="$arg_s3_dest_alias:$arg_s3_dest" || s3_dest="$arg_s3_dest"

		cmd="${command#s3:main:rclone:}"
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" \
			rclone copy --verbose "$s3_src" "$s3_dest" \
			${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
	"s3:main:rclone:lifecycle")
		error "$title: action not supported for this s3 client"
		;;
	"s3:awscli:exec:"*)
		cmd="${command#s3:awscli:exec:}"
		"$pod_script_env_file" "run:s3:main:awscli:$cmd" --cli_cmd="exec-nontty" ${args[@]+"${args[@]}"}
		;;
	"s3:awscli:run:"*)
		cmd="${command#s3:awscli:run:}"
		"$pod_script_env_file" "run:s3:main:awscli:$cmd" --cli_cmd="run" ${args[@]+"${args[@]}"}
		;;
	"s3:main:awscli:create_bucket")
		bucket_exists="$("$pod_script_env_file" "run:s3:main:awscli:bucket_exists" ${args[@]+"${args[@]}"})"

		if [ "$bucket_exists" = "false" ]; then
			info "$title - create bucket"
			inner_cmd=( aws --profile="$arg_s3_alias" )
			inner_cmd+=( s3api --endpoint="$arg_s3_endpoint" )
			inner_cmd+=( create-bucket --bucket "$arg_s3_bucket_name" )
			inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

			info "s3 command: ${inner_cmd[*]}"

			"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		fi
		;;
	"s3:main:awscli:bucket_exists")
		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" /bin/sh <<-SHELL
			set -eou pipefail

			mkdir -p "$arg_s3_tmp_dir" >&2

			error_filename="error.\$(date '+%s').\$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log" >&2
			error_log_file="$arg_s3_tmp_dir/\$error_filename" >&2

			if ! aws s3 --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
					ls "s3://$arg_s3_bucket_name" 1>&2 2> "\$error_log_file"; then
				if grep -q 'NoSuchBucket' "\$error_log_file" >&2; then
					echo "false"
					exit 0
				else
					cat "\$error_log_file" >&2
					exit 2
				fi
			fi

			echo "true"
		SHELL
		;;
	"s3:main:awscli:rb")
		bucket_exists="$("$pod_script_env_file" "run:s3:main:awscli:bucket_exists" ${args[@]+"${args[@]}"})"

		if [ "$bucket_exists" = "false" ]; then
			>&2 echo "skipping (no_bucket)"
		elif [ "$bucket_exists" = "true" ]; then
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
		if [ -z "${arg_s3_older_than_days:-}" ]; then
			error "$title: parameter s3_older_than_days undefined"
		fi

		>&2 echo ">$arg_cli_cmd $arg_s3_service: aws rm $arg_s3_endpoint (< $arg_s3_older_than_days day(s))"
		>&2 "$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" <<-SHELL
			set -eou pipefail

			s3_max_date=''

			if [ -n "${arg_s3_older_than_days:-}" ]; then
				s3_max_date="\$(date --date="$arg_s3_older_than_days days ago" '+%F %X')"
			fi

			aws s3 --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
				ls --recursive "$arg_s3_path" \
				| awk '\$1 < "'"\$s3_max_date"'" {print \$4}' \
				| xargs -n1 -t -I 'KEY' \
					aws s3 --profile="$arg_s3_alias" --endpoint="$arg_s3_endpoint" \
						rm "$arg_s3_endpoint"/'KEY'
		SHELL
		;;
	"s3:main:awscli:cp"|"s3:main:awscli:sync")
		[ "${arg_s3_remote_src:-}" = "true" ] && s3_src="s3://$arg_s3_src" || s3_src="$arg_s3_src"
		[ "${arg_s3_remote_dest:-}" = "true" ] && s3_dest="s3://$arg_s3_dest" || s3_dest="$arg_s3_dest"

		cmd="${command#s3:main:awscli:}"

		inner_cmd=( aws --profile="$arg_s3_alias" )
		inner_cmd+=( s3 --endpoint="$arg_s3_endpoint" )
		inner_cmd+=( "$cmd" "$s3_src" "$s3_dest" )
		inner_cmd+=( ${arg_s3_opts[@]+"${arg_s3_opts[@]}"} )

		info "s3 command: ${inner_cmd[*]}"

		"$pod_script_env_file" "$arg_cli_cmd" "$arg_s3_service" "${inner_cmd[@]}"
		;;
	"s3:main:awscli:lifecycle")
		if [ -z "${arg_s3_lifecycle_file:-}" ]; then
			error "$title: parameter s3_lifecycle_file undefined"
		elif [ ! -f "${pod_layer_dir}/env/awscli/etc/${arg_s3_lifecycle_file:-}" ]; then
			error "$title: s3_lifecycle_file ($arg_s3_lifecycle_file) not found"
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