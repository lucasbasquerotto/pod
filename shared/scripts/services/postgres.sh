#!/bin/bash
set -eou pipefail

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
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

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
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_remote ) arg_db_remote="${OPTARG:-}" ;;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_file_name ) arg_db_file_name="${OPTARG:-}" ;;
		db_backup_pit ) arg_db_backup_pit="${OPTARG:-}" ;;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"db:main:postgres:connect_main")
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		if [ "${arg_db_cmd:-}" != "run" ]; then
			"$pod_script_env_file" up "$arg_db_service"
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" \
			bash "$inner_run_file" "inner:service:postgres:connect_main" ${args[@]+"${args[@]}"}
		;;
	"inner:service:postgres:connect_main")
		end=$((SECONDS+arg_db_connect_wait_secs))

		while [ $SECONDS -lt $end ]; do
			current=$((end-SECONDS))
			msg="$arg_db_connect_wait_secs seconds - $current second(s) remaining"
			>&2 echo "wait for the database $arg_db_name to be ready ($msg)"

			if [ "${arg_db_remote:-}" = "true" ]; then
				if pg_isready \
					--dbname="$arg_db_name" \
					--host="$arg_db_host" \
					--port="$arg_db_port" \
					--username="$arg_db_user"
				then
					exit
				fi
			else
				if pg_isready --dbname="$arg_db_name"; then
					exit
				fi
			fi

			sleep "${arg_connection_sleep:-5}"
		done

		msg="dbname=$arg_db_name, host=$arg_db_host, port=$arg_db_port"
		error "can't connect to the database ($msg)"
		;;
	"db:main:postgres:connect")
		end_after="$((SECONDS+10))"
		"$pod_script_env_file" "db:main:postgres:connect_main" ${args[@]+"${args[@]}"} >&2 ||:

		if [ "$SECONDS" -lt "$end_after" ]; then
			echo "waiting because of fast first error..." >&2
			sleep 5
			"$pod_script_env_file" "db:main:postgres:connect_main" ${args[@]+"${args[@]}"} >&2
		fi
		;;
	"db:main:postgres:tables:count")
		if [ "${arg_db_cmd:-}" != "run" ]; then
			"$pod_script_env_file" up "$arg_db_service"
		fi

		cmd_args=( 'exec-nontty' )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( 'run' )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" \
			bash "$inner_run_file" "inner:service:postgres:tables:count" ${args[@]+"${args[@]}"}
		;;
	"inner:service:postgres:tables:count")
		sql_tables="select count(*) from information_schema.tables where table_schema = 'public'"
		re_number='^[0-9]+$'

		if [ "${arg_db_remote:-}" = "true" ]; then
			sql_output="$(psql \
				--host="$arg_db_host" \
				--port="$arg_db_port" \ \
				--username="$arg_db_user" \
				--dbname="$arg_db_name" \
				--tuples-only --command "$sql_tables" 2>&1)" ||:
		else
			sql_output="$(psql -d "$arg_db_name" -t -c "$sql_tables" 2>&1)" ||:
		fi

		tables=""

		if [ -n "$sql_output" ]; then
			tables="$(echo "$sql_output" | tail -n 1 | awk '{$1=$1;print}')"
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			tables=""
		fi

		if [ -z "$tables" ]; then
			error "$title: Couldn't verify number of tables in the database $arg_db_name - output:\n$sql_output"
		fi

		echo "$tables"
		;;
	"db:main:postgres:restore:verify")
		"$pod_script_env_file" "db:main:postgres:connect" ${args[@]+"${args[@]}"} >&2

		tables="$("$pod_script_env_file" "db:main:postgres:tables:count" ${args[@]+"${args[@]}"})"

		>&2 echo "$tables tables found"

		if [ "$tables" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:main:postgres:restore:file")
		if [ -z "${arg_db_task_base_dir:-}" ]; then
			error "$title: arg_db_task_base_dir not specified"
		fi

		if [ -z "${arg_db_file_name:-}" ]; then
			error "$title: arg_db_file_name not specified"
		fi

		db_file="$arg_db_task_base_dir/$arg_db_file_name"

		"$pod_script_env_file" up "$arg_db_service"

		"$pod_script_env_file" exec-nontty "$arg_db_service" \
			pg_restore --verbose -Fc -j 8 --dbname="$arg_db_name" "$db_file"
		;;
	"db:main:postgres:restore:wale")
		"$pod_script_env_file" up "$arg_db_service"

		"$pod_script_env_file" exec-nontty "$arg_db_service" \
			/usr/bin/envdir /etc/wal-e.d/env /usr/bin/wal-e backup-fetch /var/lib/postgresql/data "${arg_db_backup_pit:-LATEST}"
		;;
	"db:main:postgres:backup:file")
		"$pod_script_env_file" up "$arg_db_service"

		backup_file="$arg_db_task_base_dir/$arg_db_file_name"

		info "$command: $arg_db_service - backup to file $backup_file (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" mkdir -p "$(dirname -- "$backup_file")"
		"$pod_script_env_file" exec-nontty "$arg_db_service" pg_dump -Fc -Z 0 --file="$backup_file" "$arg_db_name"

		echo "$backup_file"
		;;
	"db:main:postgres:backup:wale")
		"$pod_script_env_file" up "$arg_db_service"

		info "$command: $arg_db_service - backup using wal-e"
		"$pod_script_env_file" exec-nontty "$arg_db_service" \
			/usr/bin/envdir /etc/wal-e.d/env /usr/bin/wal-e backup-push /var/lib/postgresql/data

		echo "$backup_file"
		;;
	*)
		error "$command: invalid command"
		;;
esac
