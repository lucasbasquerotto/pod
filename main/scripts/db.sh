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
	error "No command entered (db)."
fi

shift;

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}";;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		db_sql_file_name ) arg_db_sql_file_name="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"db:restore:verify:mysql")
		re_number='^[0-9]+$'

		"$pod_script_env_file" up "$arg_db_service"
		
		sql_tables="select count(*) from information_schema.tables where table_schema = '$arg_db_name'"
		sql_output="$("$pod_script_env_file" exec-nontty "$arg_db_service" \
			mysql -u "$arg_db_user" -p"$arg_db_pass" -N -e "$sql_tables")" ||:
		tables=""

		if [ -n "$sql_output" ]; then
			tables="$(echo "$sql_output" | tail -n 1)"
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			tables=""
		fi

		if [ -z "$tables" ]; then
			info "$command - wait for db to be ready ($arg_db_connect_wait_secs seconds)"
			sleep "$arg_db_connect_wait_secs"
			sql_output="$("$pod_script_env_file" exec-nontty "$arg_db_service" \
				mysql -u "$arg_db_user" -p"$arg_db_pass" -N -e "$sql_tables")" ||:

			if [ -n "$sql_output" ]; then
				tables="$(echo "$sql_output" | tail -n 1)"
			fi
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			error "$command: Couldn't verify number of tables in database - output: $sql_output"
		fi

		if [ "$tables" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:restore:file:mysql")    
		if [ -z "$arg_db_task_base_dir" ]; then
			error "$command: arg_db_task_base_dir not specified"
		fi

		if [ -z "$arg_db_sql_file_name" ]; then
			error "$command: arg_db_sql_file_name not specified"
		fi

		db_sql_file="$arg_db_task_base_dir/$arg_db_sql_file_name"

		"$pod_script_env_file" up "$arg_db_service"

		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail

			function error {
				msg="\$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: \${1:-}"
				>&2 echo -e "${RED}\${msg}${NC}"
				exit 2
			}

			extension=${db_sql_file##*.}

			if [ "\$extension" != "sql" ]; then
				error "$command: db file extension should be sql - found: \$extension ($db_sql_file)"
			fi

			if [ ! -f "$db_sql_file" ]; then
				error "$command: db file not found: $db_sql_file"
			fi
			
			mysql -u "$arg_db_user" -p"$arg_db_pass" -e "CREATE DATABASE IF NOT EXISTS $arg_db_name;"
			pv "$db_sql_file" | mysql -u "$arg_db_user" -p"$arg_db_pass" "$arg_db_name"
		SHELL
		;;
	"db:backup:file:mysql")
		"$pod_script_env_file" up "$arg_db_service"

		backup_file="$arg_db_task_base_dir/$arg_db_sql_file_name"

		info "$command: $arg_db_service - backup to file $backup_file (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mkdir -p "$(dirname -- "$backup_file")"
			mysqldump -u "$arg_db_user" -p"$arg_db_pass" "$arg_db_name" > "$backup_file"
		SHELL
		;;
	"db:connection:pg")
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL
			function error {
				msg="\$(date '+%F %T') \${1:-}"
				>&2 echo -e "${RED}$command: \${msg}${NC}"
				exit 2
			}

			set -eou pipefail
			
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
		error "$command: Invalid command"
		;;
esac