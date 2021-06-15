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
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}" ;;
		toolbox_service ) ;;
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_remote ) arg_db_remote="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}" ;;
		authentication_database ) arg_authentication_database="${OPTARG:-}" ;;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"db:main:mongo:connect")
		"$pod_script_env_file" "db:main:mongo:collections:count" ${args[@]+"${args[@]}"} > /dev/null
		;;
	"db:main:mongo:collections:count")
		"$pod_script_env_file" up "$arg_db_service"

		re_number='^[0-9]+$'
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			function error {
				>&2 echo -e "\$(date '+%F %T') (inside) - \${*}"
				exit 2
			}

			end=\$((SECONDS+$arg_db_connect_wait_secs))
			tables=""

			while [ -z "\$tables" ] && [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="$arg_db_connect_wait_secs seconds - \$current second(s) remaining"

				if [ "${arg_db_remote:-}" = "true" ]; then
					>&2 echo "wait for the remote database $arg_db_name (at $arg_db_host) to be ready (\$msg)"
					output="\$(mongo "mongo/$arg_db_name" \
						--host="$arg_db_host" \
						--port="$arg_db_port" \
						--username="$arg_db_user" \
						--password="$arg_db_pass" \
						--authenticationDatabase="$arg_authentication_database" \
						--eval "db.stats().collections" 2>&1)" ||:
				else
					>&2 echo "wait for the local database $arg_db_name to be ready (\$msg)"
					output="\$(mongo "mongo/$arg_db_name" \
						--username="$arg_db_user" \
						--password="$arg_db_pass" \
						--authenticationDatabase="$arg_authentication_database" \
						--eval "db.stats().collections" 2>&1)" ||:
				fi

				if [ -n "\$output" ]; then
					collections="\$(echo "\$output" | tail -n 1)"
				fi

				if ! [[ \$collections =~ $re_number ]] ; then
					collections=""
				fi

				if [ -z "\$collections" ]; then
					sleep "${arg_connection_sleep:-5}"
				else
					echo "\$collections"
					exit
				fi
			done

			msg="Couldn't verify number of collections in the database $arg_db_name"
			error "$title: \$msg - output:\n\$output"
		SHELL
		;;
	"db:main:mongo:restore:verify")
		collections="$("$pod_script_env_file" "db:main:mongo:collections:count" ${args[@]+"${args[@]}"})"

		>&2 echo "$collections collections found"

		if [ "$collections" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:main:mongo:backup")
		"$pod_script_env_file" up "$arg_db_service"

		msg="backup database ($arg_db_name)"
		msg="$msg to directory $arg_db_task_base_dir/$arg_db_name (inside service)"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail
			rm -rf "$arg_db_task_base_dir/$arg_db_name"
			mkdir -p "$arg_db_task_base_dir"
			mongodump \
				--host="$arg_db_host" \
				--port="$arg_db_port" \
				--username="$arg_db_user" \
				--password="$arg_db_pass" \
				--db="$arg_db_name" \
				--authenticationDatabase="$arg_authentication_database" \
				--out="$arg_db_task_base_dir"
		SHELL

		echo ""
		;;
	"db:main:mongo:restore:dir")
		"$pod_script_env_file" up "$arg_db_service"

		info "$command: $arg_db_service - restore from $arg_db_task_base_dir (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail
			mongorestore \
				--host="$arg_db_host" \
				--port="$arg_db_port" \
				--username="$arg_db_user" \
				--password="$arg_db_pass" \
				--nsInclude="$arg_db_name.*" \
				--authenticationDatabase="$arg_authentication_database" \
				--objcheck \
				--stopOnError \
				"$arg_db_task_base_dir"
		SHELL
		;;
	*)
		error "$command: invalid command"
		;;
esac
