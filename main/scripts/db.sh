#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_script_env_file="$POD_SCRIPT_ENV_FILE"

GRAY="\033[0;90m"
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	msg="$(date '+%F %T') - ${1:-}"
	>&2 echo -e "${GRAY}${msg}${NC}"
}

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered."
fi

shift;

args=("$@")

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		subtask_cmd ) arg_subtask_cmd="${OPTARG:-}";;
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}";;
		authentication_database ) arg_authentication_database="${OPTARG:-}";;
		db_remote ) arg_db_remote="${OPTARG:-}";;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		db_file_name ) arg_db_file_name="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

case "$command" in
	"db:main:connect:mysql")
		"$pod_script_env_file" "run:db:main:tables:count:mysql" ${args[@]+"${args[@]}"} > /dev/null
		;;
	"db:main:tables:count:mysql")
		"$pod_script_env_file" up "$arg_db_service"

		sql_tables="select count(*) from information_schema.tables where table_schema = '$arg_db_name'"
		re_number='^[0-9]+$'
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail

			function info {
				msg="\$(date '+%F %T') - \${1:-}"
				>&2 echo -e "${GRAY}$command: \${msg}${NC}"
			}

			function error {
				msg="\$(date '+%F %T') \${1:-}"
				>&2 echo -e "${RED}$command: \${msg}${NC}"
				exit 2
			}

			end=\$((SECONDS+$arg_db_connect_wait_secs))
			tables=""

			while [ -z "\$tables" ] && [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="$arg_db_connect_wait_secs seconds - \$current second(s) remaining"

				if [ "${arg_db_remote:-}" = "true" ]; then
					info "$title - wait for the remote database $arg_db_name (at $arg_db_host) to be ready (\$msg)"
					sql_output="\$(mysql \
						--user="$arg_db_user" \
						--host="$arg_db_host" \
						--port="$arg_db_port" \
						--password="$arg_db_pass" \
						-N -e "$sql_tables" 2>&1)" ||:
				else
					info "$title - wait for the local database $arg_db_name to be ready (\$msg)"
					sql_output="\$(mysql -u "$arg_db_user" -p"$arg_db_pass" -N -e "$sql_tables" 2>&1)" ||:
				fi

				if [ -n "\$sql_output" ]; then
					tables="\$(echo "\$sql_output" | tail -n 1)"
				fi

				if ! [[ \$tables =~ $re_number ]] ; then
					tables=""
				fi

				if [ -z "\$tables" ]; then
					sleep "${arg_connection_sleep:-5}"
				else
					echo "\$tables"
					exit
				fi
			done

			error "$title: Couldn't verify number of tables in the database $arg_db_name - output:\n\$sql_output"
		SHELL
		;;
	"db:restore:verify:mysql")
		tables="$("$pod_script_env_file" "run:db:main:tables:count:mysql" ${args[@]+"${args[@]}"})"

		>&2 echo "$tables tables found"

		if [ "$tables" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:restore:file:mysql")
		if [ -z "$arg_db_task_base_dir" ]; then
			error "$title: arg_db_task_base_dir not specified"
		fi

		if [ -z "$arg_db_file_name" ]; then
			error "$title: arg_db_file_name not specified"
		fi

		db_file="$arg_db_task_base_dir/$arg_db_file_name"

		"$pod_script_env_file" up "$arg_db_service"

		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail

			function error {
				msg="\$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: \${1:-}"
				>&2 echo -e "${RED}\${msg}${NC}"
				exit 2
			}

			extension=${db_file##*.}

			if [ "\$extension" != "sql" ]; then
				error "$title: db file extension should be sql - found: \$extension ($db_file)"
			fi

			if [ ! -f "$db_file" ]; then
				error "$title: db file not found: $db_file"
			fi

			cmd="cat"

			if command -v pv >/dev/null 2>&1; then
				cmd="pv"
			fi

			mysql -u "$arg_db_user" -p"$arg_db_pass" -e "CREATE DATABASE IF NOT EXISTS $arg_db_name;"
			"\$cmd" "$db_file" | mysql -u "$arg_db_user" -p"$arg_db_pass" "$arg_db_name"
		SHELL
		;;
	"db:backup:file:mysql")
		"$pod_script_env_file" up "$arg_db_service"

		backup_file="$arg_db_task_base_dir/$arg_db_file_name"

		info "$title: $arg_db_service - backup to file $backup_file (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mkdir -p "$(dirname -- "$backup_file")"
			mysqldump -u "$arg_db_user" -p"$arg_db_pass" "$arg_db_name" > "$backup_file"
		SHELL
		;;
	"db:main:connect:mongo")
		"$pod_script_env_file" "run:db:main:collections:count:mongo" ${args[@]+"${args[@]}"} > /dev/null
		;;
	"db:main:collections:count:mongo")
		"$pod_script_env_file" up "$arg_db_service"

		re_number='^[0-9]+$'
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail

			function info {
				msg="\$(date '+%F %T') - \${1:-}"
				>&2 echo -e "${GRAY}$command: \${msg}${NC}"
			}

			function error {
				msg="\$(date '+%F %T') \${1:-}"
				>&2 echo -e "${RED}$command: \${msg}${NC}"
				exit 2
			}

			end=\$((SECONDS+$arg_db_connect_wait_secs))
			tables=""

			while [ -z "\$tables" ] && [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="$arg_db_connect_wait_secs seconds - \$current second(s) remaining"

				if [ "${arg_db_remote:-}" = "true" ]; then
					info "$title - wait for the remote database $arg_db_name (at $arg_db_host) to be ready (\$msg)"
					output="\$(mongo "mongo/$arg_db_name" \
						--host="$arg_db_host" \
						--port="$arg_db_port" \
						--username="$arg_db_user" \
						--password="$arg_db_pass" \
						--authenticationDatabase="$arg_authentication_database" \
						--eval "db.stats().collections" 2>&1)" ||:
				else
					info "$title - wait for the local database $arg_db_name to be ready (\$msg)"
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
	"db:restore:verify:mongo")
		collections="$("$pod_script_env_file" "run:db:main:collections:count:mongo" ${args[@]+"${args[@]}"})"

		>&2 echo "$collections collections found"

		if [ "$collections" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:backup:mongo")
		"$pod_script_env_file" up "$arg_db_service"

		msg="backup database ($arg_db_name)"
		msg="$msg to directory $arg_db_task_base_dir/$arg_db_name (inside service)"
		info "$title: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
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
		;;
	"db:restore:mongo")
		"$pod_script_env_file" up "$arg_db_service"

		info "$title: $arg_db_service - restore from $arg_db_task_base_dir (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mongorestore \
				--host="$arg_db_host" \
				--port="$arg_db_port" \
				--username="$arg_db_user" \
				--password="$arg_db_pass" \
				--nsInclude="$arg_db_name.*" \
				--authenticationDatabase="$arg_authentication_database" \
				"$arg_db_task_base_dir"
		SHELL
		;;
	"db:connection:pg")
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail

			function error {
				msg="\$(date '+%F %T') \${1:-}"
				>&2 echo -e "${RED}$command: \${msg}${NC}"
				exit 2
			}

			end=\$((SECONDS+$arg_db_connect_wait_secs))

			while [ \$SECONDS -lt \$end ]; do
				if pg_isready \
					--dbname="$arg_db_name" \
					--host="$arg_db_host" \
					--port="$arg_db_port" \
					--username="$arg_db_user"
				then
					exit
				fi

				sleep "${arg_connection_sleep:-5}"
			done

			error "can't connect to database (dbname=$arg_db_name, host=$arg_db_host, port=$arg_db_port, username=$arg_db_user)"
		SHELL
		;;
	*)
		error "$title: Invalid command"
		;;
esac