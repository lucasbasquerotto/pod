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
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_cmd ) arg_db_cmd="${OPTARG:-}" ;;
		db_name ) arg_db_name="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_user ) arg_db_user="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}";;
		db_tls ) arg_db_tls="${OPTARG:-}" ;;
		db_tls_ca_cert ) arg_db_tls_ca_cert="${OPTARG:-}" ;;
		authentication_database ) arg_authentication_database="${OPTARG:-}";;
		db_remote ) arg_db_remote="${OPTARG:-}";;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		db_file_name ) arg_db_file_name="${OPTARG:-}" ;;
		connection_sleep ) arg_connection_sleep="${OPTARG:-}" ;;
		snapshot_type ) arg_snapshot_type="${OPTARG:-}" ;;
		repository_name ) arg_repository_name="${OPTARG:-}" ;;
		snapshot_name ) arg_snapshot_name="${OPTARG:-}" ;;
		bucket_name ) arg_bucket_name="${OPTARG:-}" ;;
		bucket_path ) arg_bucket_path="${OPTARG:-}" ;;
		db_index_prefix ) arg_db_index_prefix="${OPTARG:-}" ;;
		db_args ) arg_db_args="${OPTARG:-}" ;;
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"db:main:connect:mysql")
		"$pod_script_env_file" "run:db:main:tables:count:mysql" ${args[@]+"${args[@]}"} > /dev/null
		;;
	"db:main:tables:count:mysql")
		if [ "${arg_db_cmd:-}" != "run" ]; then
			"$pod_script_env_file" up "$arg_db_service"
		fi

		sql_tables="select count(*) from information_schema.tables where table_schema = '$arg_db_name'"
		re_number='^[0-9]+$'
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

			end=\$((SECONDS+$arg_db_connect_wait_secs))
			tables=""

			while [ -z "\$tables" ] && [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="$arg_db_connect_wait_secs seconds - \$current second(s) remaining"

				if [ "${arg_db_remote:-}" = "true" ]; then
					>&2 echo "wait for the remote database $arg_db_name (at $arg_db_host) to be ready (\$msg)"
					sql_output="\$(mysql \
						--host="$arg_db_host" \
						--port="$arg_db_port" \
						--user="$arg_db_user" \
						--password="$arg_db_pass" \
						-N -e "$sql_tables" 2>&1)" ||:
				else
					>&2 echo "wait for the local database $arg_db_name to be ready (\$msg)"
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
	"db:backup:file:mysql")
		"$pod_script_env_file" up "$arg_db_service"

		backup_file="$arg_db_task_base_dir/$arg_db_file_name"

		info "$command: $arg_db_service - backup to file $backup_file (inside service)"
		"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL >&2 || error "$command"
			set -eou pipefail
			mkdir -p "$(dirname -- "$backup_file")"
			mysqldump -u "$arg_db_user" -p"$arg_db_pass" "$arg_db_name" > "$backup_file"
		SHELL

		echo "$backup_file"
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
	"db:restore:mongo:dir")
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
	"db:connection:pg")
		cmd_args=( "exec-nontty" )

		if [ "${arg_db_cmd:-}" = "run" ]; then
			cmd_args=( "run" )
		fi

		"$pod_script_env_file" "${cmd_args[@]}" "$arg_db_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			function error {
				>&2 echo -e "\$(date '+%F %T') - \${BASH_SOURCE[0]}: line \${BASH_LINENO[0]}: \${*}"
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
	"db:repository:elasticsearch")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_db_service"

		es_args=()

		if [ "${arg_db_tls:-}" = 'true' ]; then
			elasticsearch_password="$("$pod_script_env_file" "run:db:pass:elasticsearch" ${args[@]+"${args[@]}"})"

			es_args+=( --user elastic )
			es_args+=( --password "$elasticsearch_password" )

			if [ -n "${arg_db_tls_ca_cert:-}" ]; then
				es_args+=( --ca-certificate="${arg_db_tls_ca_cert:-}" )
			fi
		fi

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port/_snapshot"
		url="$url_base/$arg_repository_name?pretty"

		if [ -z "${arg_snapshot_type:-}" ]; then
			error "$title: snapshot_type parameter not defined (repository_name=$arg_repository_name)"
		fi

		data='
			{
				"type": "'"$arg_snapshot_type"'",
				"settings": {
					"location": "'"$arg_db_task_base_dir"'"
				}
			}
			'

		if [ "${arg_snapshot_type:-}" = 's3' ]; then
			data='
				{
					"type": "'"$arg_snapshot_type"'",
					"settings": {
						"location": "'"$arg_db_task_base_dir"'",
						"bucket": "'"$arg_bucket_name"'",
						"base_path": "'"${arg_bucket_path:-}"'"
					}
				}
				'
		fi

		msg="create a repository for snapshots ($arg_repository_name - $arg_snapshot_type)"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			wget --content-on-error -O- \
				--header='Content-Type:application/json' \
				--post-data="$data" \
				${es_args[@]+"${es_args[@]}"} \
				"$url"
		;;
	"db:backup:elasticsearch")
		"$pod_script_env_file" "run:db:repository:elasticsearch" ${args[@]+"${args[@]}"} >&2

		elasticsearch_password="$("$pod_script_env_file" "run:db:pass:elasticsearch" ${args[@]+"${args[@]}"})"

		snapshot_name_path="$("$pod_script_env_file" "run:util:urlencode" \
			--value="$arg_snapshot_name")"

		es_args=()

		if [ "${arg_db_tls:-}" = 'true' ]; then
			es_args+=( --user elastic )
			es_args+=( --password "$elasticsearch_password" )

			if [ -n "${arg_db_tls_ca_cert:-}" ]; then
				es_args+=( --ca-certificate="${arg_db_tls_ca_cert:-}" )
			fi
		fi

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port/_snapshot"
		url_path="$url_base/$arg_repository_name/$snapshot_name_path"
		url="$url_path?wait_for_completion=true&pretty"

		msg="create a snapshot of the database ($arg_repository_name/$arg_snapshot_name)"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			wget \
				--content-on-error -O- --method=PUT
				${es_args[@]+"${es_args[@]}"} \
				"$url" \
			>&2

		if [ "$arg_snapshot_type" = 'fs' ]; then
			echo "$arg_db_task_base_dir"
		fi
		;;
	"db:pass:elasticsearch")
		if [ "${arg_db_tls:-}" = 'true' ]; then
			"$pod_script_env_file" exec-nontty "$arg_db_service" /bin/bash <<-SHELL || error "$command"
				set -eou pipefail
				pass_file="\$(printenv | grep ELASTIC_PASSWORD_FILE | cut -f 2- -d '=' ||:)"

				if [ -n "\$pass_file" ]; then
					cat "\$pass_file"
				else
					printenv | grep ELASTIC_PASSWORD | cut -f 2- -d '=' ||:
				fi
			SHELL
		fi
		;;
	"db:ready:elasticsearch")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_db_service" > /dev/null

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port"
		url="$url_base/_cluster/health?wait_for_status=yellow"

		elasticsearch_password="$("$pod_script_env_file" "run:db:pass:elasticsearch" ${args[@]+"${args[@]}"})"

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			timeout="${arg_db_connect_wait_secs:-150}"
			end=\$((SECONDS+\$timeout))
			success=false

			while [ \$SECONDS -lt \$end ]; do
				current=\$((end-SECONDS))
				msg="\$timeout seconds - \$current second(s) remaining"
				>&2 echo "wait for elasticsearch to be ready (\$msg)"


				if curl --fail -sS -u "elastic:$elasticsearch_password" \
						--cacert "${arg_db_tls_ca_cert:-}" \
						"$url" >&2; then
					success=true
					echo '' >&2
					echo "> elasticsearch is ready" >&2
					break
				fi

				sleep 5
			done

			if [ "\$success" != 'true' ]; then
				echo "timeout while waiting for elasticsearch" >&2
				exit 2
			fi
		SHELL
		;;
	"db:restore:verify:elasticsearch")
		"$pod_script_env_file" "run:db:ready:elasticsearch" ${args[@]+"${args[@]}"}

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port/_cat/indices"
		url="$url_base/${arg_db_index_prefix}*?s=index&pretty"

		elasticsearch_password="$("$pod_script_env_file" "run:db:pass:elasticsearch" ${args[@]+"${args[@]}"})"

		msg="verify if the database has indexes with prefix ($arg_db_index_prefix)"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			echo "accessing the url $url..." >&2

			if [ "${arg_db_tls:-}" = 'true' ]; then
				output="\$(curl --fail -sS \
						-u "elastic:$elasticsearch_password" \
						--cacert "${arg_db_tls_ca_cert:-}" \
						"$url" \
					)"
			else
				output="\$(curl --fail -sS "$url")"
			fi

			lines="\$(echo "\$output" | wc -l)"

			if [ -n "\$output" ] && [[ "\$lines" -ge 1 ]]; then
				echo "true"
			else
				echo "false"
			fi
		SHELL
		;;
	"db:restore:elasticsearch")
		"$pod_script_env_file" "run:db:repository:elasticsearch" ${args[@]+"${args[@]}"}

		es_args=()

		if [ "${arg_db_tls:-}" = 'true' ]; then
			elasticsearch_password="$("$pod_script_env_file" "run:db:pass:elasticsearch" ${args[@]+"${args[@]}"})"

			es_args+=( --user elastic )
			es_args+=( --password "$elasticsearch_password" )

			if [ -n "${arg_db_tls_ca_cert:-}" ]; then
				es_args+=( --ca-certificate="${arg_db_tls_ca_cert:-}" )
			fi
		fi

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port/_snapshot"
		url_path="$url_base/$arg_repository_name/$arg_snapshot_name/_restore"
		url="$url_path?wait_for_completion=true&pretty"

		db_args="${arg_db_args:-}"

		if [ -z "${arg_db_args:-}" ]; then
			db_args='{}'
		fi

		msg="restore a snapshot of the database ($arg_repository_name/$arg_snapshot_name)"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			wget --content-on-error -O- \
				--header='Content-Type:application/json' \
				--post-data="$db_args" \
				${es_args[@]+"${es_args[@]}"} \
				"$url"
		;;
	"db:backup:prometheus")
		url="http://$arg_db_host:$arg_db_port/api/v1/admin/tsdb/snapshot"

		msg="create a snapshot of the prometheus data"
		info "$command: $arg_db_service - $msg"
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			wget --content-on-error -qO- --method=POST "$url"

		echo ""
		;;
	*)
		error "$title: Invalid command"
		;;
esac
