#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

RED='\033[0;31m'
NC='\033[0m' # No Color

command="${1:-}"

if [ -z "$command" ]; then
	echo -e "${RED}No command entered (db).${NC}"
	exit 1
fi

shift;

re_number='^[0-9]+$'

case "$command" in
	"setup:db:verify:mysql")
		sql_tables="select count(*) from information_schema.tables where table_schema = '$var_db_name'"
		sql_output="$("$pod_script_env_file" exec-nontty "$var_db_service" \
			mysql -u "$var_db_user" -p"$var_db_pass" -N -e "$sql_tables")" ||:
		tables=""

		if [ ! -z "$sql_output" ]; then
			tables="$(echo "$sql_output" | tail -n 1)"
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			tables=""
		fi

		if [ -z "$tables" ]; then
			>&2 echo "$(date '+%F %X') - $command - wait for db to be ready"
			sleep 60
			sql_output="$("$pod_script_env_file" exec-nontty "$var_db_service" \
				mysql -u "$var_db_user" -p"$var_db_pass" -N -e "$sql_tables")" ||:

			if [ ! -z "$sql_output" ]; then
				tables="$(echo "$sql_output" | tail -n 1)"
			fi
		fi

		if ! [[ $tables =~ $re_number ]] ; then
			msg="Could nor verify number of tables in database - output: $sql_output"
			echo -e "${RED}$(date '+%F %X') - ${msg}${NC}"
			exit 1
		fi

		if [ "$tables" != "0" ]; then
			echo "true"
		else
			echo "false"
		fi
		;;
  "setup:db:local:file:mysql")
		setup_db_sql_file="${1:-}"

		if [ -z "$setup_db_sql_file" ]; then
			echo -e "${RED}[setup:db:mysql] setup_db_sql_file not specified${NC}"
			exit 1
		fi

		"$pod_script_env_file" exec-nontty "$var_db_service" /bin/bash <<-SHELL
			set -eou pipefail

      extension=${setup_db_sql_file##*.}

      if [ "\$extension" != "sql" ]; then
        msg="$command: db file extension should be sql - found: \$extension ($setup_db_sql_file)"
        echo -e "${RED}$(date '+%F %X') - \${msg}${NC}"
        exit 1
      fi

      if [ ! -f "$setup_db_sql_file" ]; then
        msg="$command: db file not found: $setup_db_sql_file"
        echo -e "${RED}$(date '+%F %X') - \${msg}${NC}"
        exit 1
      fi
      
			mysql -u "$var_db_user" -p"$var_db_pass" -e "CREATE DATABASE IF NOT EXISTS $var_db_name;"
			pv "$setup_db_sql_file" | mysql -u "$var_db_user" -p"$var_db_pass" "$var_db_name"
		SHELL
		;;
  "backup:db:local:mysql")
		"$pod_script_env_file" exec-nontty "$var_db_service" /bin/bash <<-SHELL
			set -eou pipefail
			mysqldump -u "$var_db_user" -p"$var_db_pass" "$var_db_name" > "/$var_db_backup_dir/$var_db_name.sql"
		SHELL
    ;;
  *)
		echo -e "${RED}Invalid command: $command ${NC}"
		exit 1
    ;;
esac