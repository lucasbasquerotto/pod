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
		toolbox_service ) arg_toolbox_service="${OPTARG:-}" ;;
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}" ;;
		db_remote ) arg_db_remote="${OPTARG:-}" ;;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_file_name ) arg_db_file_name="${OPTARG:-}" ;;

		max_amount ) arg_max_amount="${OPTARG:-}" ;;
		log_file ) arg_log_file="${OPTARG:-}" ;;

		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"db:main:mysql:connect")
		"$pod_script_env_file" "db:main:mysql:tables:count" ${args[@]+"${args[@]}"} > /dev/null
		;;
	"db:main:mysql:restore:verify")
		tables="$("$pod_script_env_file" "db:main:mysql:tables:count" ${args[@]+"${args[@]}"})"

		re_number='^[0-9]+$'
		error_msg='number of tables in the database could not be determined'

		if  [ -z "$tables" ]; then
			error "$command: $error_msg (empty response)"
		elif ! [[ $tables =~ $re_number ]]; then
			error "$command: $error_msg (invalid: $tables)"
		fi

		>&2 echo "$tables tables found"

		if [ "$tables" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:main:mysql:tables:count")
		if [ "${arg_db_cmd:-}" != "run" ]; then
			"$pod_script_env_file" up "$arg_db_service"
		fi

		sql_tables="select count(*) from information_schema.tables where table_schema = '${arg_db_name:-}'"
		db_connect_wait_secs="${arg_db_connect_wait_secs:-30}"
		cmd_args=( 'exec-nontty' )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( 'run' )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			function error {
				>&2 echo -e "\$(date '+%F %T') - \${BASH_SOURCE[0]}: line \${BASH_LINENO[0]}: \${*}"
				exit 2
			}

			end=\$((SECONDS+$db_connect_wait_secs))
			tables=""

			while [ -z "\$tables" ] && [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="$db_connect_wait_secs seconds - \$current second(s) remaining"

				pass_arg=()
				[ -n "${arg_db_pass:-}" ] && pass_arg+=( --password="${arg_db_pass:-}" )

				if [ "${arg_db_remote:-}" = "true" ]; then
					>&2 echo "wait for the remote database ${arg_db_name:-} (at ${arg_db_host:-}) to be ready (\$msg)"
					sql_output="\$(mysql \
						--host="${arg_db_host:-}" \
						--port="${arg_db_port:-}" \
						--user="${arg_db_user:-}" \
						\${pass_arg[@]+"\${pass_arg[@]}"} \
						-N -e "$sql_tables" ||:)"
				else
					>&2 echo "wait for the local database ${arg_db_name:-} to be ready (\$msg)"
					sql_output="\$(mysql -u "${arg_db_user:-}" \${pass_arg[@]+"\${pass_arg[@]}"} -N -e "$sql_tables" ||:)"
				fi

				if [ -n "\$sql_output" ]; then
					tables="\$(echo "\$sql_output" | tail -n 1)"
				fi

				re_number='^[0-9]+$'

				if ! [[ \$tables =~ \$re_number ]] ; then
					tables=""
				fi

				if [ -z "\$tables" ]; then
					sleep "${arg_connection_sleep:-5}"
				else
					echo "\$tables"
					exit
				fi
			done

			error "$title: couldn't verify number of tables in the database ${arg_db_name:-} - output:\n\$sql_output"
		SHELL
		;;
	"db:main:mysql:restore:file")
		if [ -z "${arg_db_task_base_dir:-}" ]; then
			error "$title: arg_db_task_base_dir not specified"
		fi

		if [ -z "${arg_db_file_name:-}" ]; then
			error "$title: arg_db_file_name not specified"
		fi

		db_file="$arg_db_task_base_dir/$arg_db_file_name"

		"$pod_script_env_file" up "$arg_db_service"

		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			function error {
				>&2 echo -e "\$(date '+%F %T') - \${BASH_SOURCE[0]}: line \${BASH_LINENO[0]}: \${*}"
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
	"db:main:mysql:backup:file")
		"$pod_script_env_file" up "$arg_db_service"

		backup_file="$arg_db_task_base_dir/$arg_db_file_name"

		info "$command: $arg_db_service - backup to file $backup_file (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL >&2 || error "$command"
			set -eou pipefail
			mkdir -p "$(dirname -- "$backup_file")"
			mysqldump -u "${arg_db_user:-}" -p"${arg_db_pass:-}" "${arg_db_name:-}" > "$backup_file"
		SHELL

		echo "$backup_file"
		;;
	"service:mysql:log:slow:summary")
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			echo -e "##############################################################################################################"
			echo -e "##############################################################################################################"
			echo -e "MySQL - Slow Logs"
			echo -e "--------------------------------------------------------------------------------------------------------------"
			echo -e "Path: $arg_log_file"
			echo -e "Limit: $arg_max_amount"

			if [ -f "$arg_log_file" ]; then
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_qtd_slow_logs="\$( \
					{ grep '^# User@Host' "$arg_log_file" \
					| awk ' \
						{ s[substr(\$3, 0, index(\$3, "["))]+=1 } END \
						{ for (key in s) { printf "%10d %s\n", s[key], key } } \
						' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_qtd_slow_logs"

				echo -e "##############################################################################################################"
				echo -e "MySQL - Slow Logs - Times with slowest logs per user"
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_slowest_logs_per_user="\$( \
					{ grep -E '^(# Time: |# User@Host: |# Query_time: )' "$arg_log_file" \
					| awk ' \
						{ \
							if (\$2 == "Time:") {time = \$3 " " \$4;} \
							else if (\$2 == "User@Host:") { \
								user = substr(\$3, 0, index(\$3, "[")); \
							} \
							else if (\$2 == "Query_time:") { \
								if (s[user] < \$3) { s[user] = \$3; t[user] = time; } \
							} \
						} END \
						{ for (key in s) { printf "%10.1f %12s %s\n", s[key], key, t[key] } } \
					' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_slowest_logs_per_user"

				echo -e "##############################################################################################################"
				echo -e "MySQL - Slow Logs - Times with slowest logs"
				echo -e "--------------------------------------------------------------------------------------------------------------"

				mysql_slowest_logs="\$( \
					{ grep -E '^(# Time: |# User@Host: |# Query_time: )' "$arg_log_file" \
					| awk '{ \
						if(\$2 == "Time:") {time = \$3 " " \$4;} \
						else if (\$2 == "User@Host:") { \
							user = substr(\$3, 0, index(\$3, "[")); \
						} \
						else if (\$2 == "Query_time:") { \
							printf "%10.1f %12s %s\n", \$3, user, time \
						} \
					}' \
					| sort -nr ||:; } | head -n "$arg_max_amount")"
				echo -e "\$mysql_slowest_logs"
			fi
		SHELL
		;;
	*)
		error "$command: invalid command"
		;;
esac
