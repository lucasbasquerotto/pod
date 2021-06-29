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
		toolbox_service ) arg_toolbox_service="${OPTARG:-}" ;;
		db_service ) arg_db_service="${OPTARG:-}" ;;
		db_connect_wait_secs) arg_db_connect_wait_secs="${OPTARG:-}" ;;
		db_tls ) arg_db_tls="${OPTARG:-}" ;;
		db_tls_ca_cert ) arg_db_tls_ca_cert="${OPTARG:-}" ;;
		db_host ) arg_db_host="${OPTARG:-}" ;;
		db_port ) arg_db_port="${OPTARG:-}" ;;
		db_pass ) arg_db_pass="${OPTARG:-}" ;;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}" ;;
		db_index_prefix ) arg_db_index_prefix="${OPTARG:-}" ;;
		repository_name ) arg_repository_name="${OPTARG:-}" ;;
		snapshot_type ) arg_snapshot_type="${OPTARG:-}" ;;
		snapshot_name ) arg_snapshot_name="${OPTARG:-}" ;;
		bucket_name ) arg_bucket_name="${OPTARG:-}" ;;
		bucket_path ) arg_bucket_path="${OPTARG:-}" ;;
		db_args ) arg_db_args="${OPTARG:-}" ;;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"db:main:elasticsearch:repository")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_db_service"

		es_args=()

		if [ "${arg_db_tls:-}" = 'true' ]; then
			elasticsearch_password="$("$pod_script_env_file" "db:main:elasticsearch:pass" ${args[@]+"${args[@]}"})"

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
	"db:main:elasticsearch:backup")
		"$pod_script_env_file" "db:main:elasticsearch:repository" ${args[@]+"${args[@]}"} >&2

		elasticsearch_password="$("$pod_script_env_file" "db:main:elasticsearch:pass" ${args[@]+"${args[@]}"})"

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
	"db:main:elasticsearch:pass")
		if [ "${arg_db_tls:-}" = 'true' ]; then
			"$pod_script_env_file" exec-nontty "$arg_db_service" \
				bash "$inner_run_file" "inner:service:elasticsearch:pass" ${args[@]+"${args[@]}"}
		fi
		;;
	"inner:service:elasticsearch:pass")
		if [ "${arg_db_tls:-}" = 'true' ]; then
			pass_file="$(printenv | grep ELASTIC_PASSWORD_FILE | cut -f 2- -d '=' ||:)"

			if [ -n "$pass_file" ]; then
				cat "$pass_file"
			else
				printenv | grep ELASTIC_PASSWORD | cut -f 2- -d '=' ||:
			fi
		fi
		;;
	"db:main:elasticsearch:ready")
		"$pod_script_env_file" up "$arg_toolbox_service" "$arg_db_service"

		db_pass="$("$inner_run_file" "db:main:elasticsearch:pass" ${args[@]+"${args[@]}"})"

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:service:elasticsearch:ready" \
			--db_pass="$db_pass" \
			${args[@]+"${args[@]}"}
		;;
	"inner:service:elasticsearch:ready")
		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port"
		url="$url_base/_cluster/health?wait_for_status=yellow"

		timeout="${arg_db_connect_wait_secs:-150}"
		end=$((SECONDS+timeout))
		success=false

		while [ $SECONDS -lt $end ]; do
			current=$((end-SECONDS))
			msg="$timeout seconds - $current second(s) remaining"
			>&2 echo "wait for elasticsearch to be ready ($msg)"

			if curl --fail --silent --show-error -u "elastic:$arg_db_pass" \
					--cacert "${arg_db_tls_ca_cert:-}" \
					"$url" >&2; then
				success=true
				echo '' >&2
				echo "> elasticsearch is ready" >&2
				break
			fi

			sleep 5
		done

		if [ "$success" != 'true' ]; then
			echo "timeout while waiting for elasticsearch" >&2
			exit 2
		fi
		;;
	"db:main:elasticsearch:restore:verify")
		db_pass="$("$inner_run_file" "db:main:elasticsearch:pass" ${args[@]+"${args[@]}"})"

		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:service:elasticsearch:restore:verify" \
			--db_pass="$db_pass" \
			${args[@]+"${args[@]}"}
		;;
	"inner:service:elasticsearch:restore:verify")
		"$pod_script_env_file" "inner:service:elasticsearch:ready" ${args[@]+"${args[@]}"}

		db_scheme='http'
		[ "${arg_db_tls:-}" = 'true' ] && db_scheme='https'

		url_base="${db_scheme}://$arg_db_host:$arg_db_port/_cat/indices"
		url="$url_base/${arg_db_index_prefix}*?s=index&pretty"

		msg="verify if the database has indexes with prefix ($arg_db_index_prefix)"
		info "$command: $arg_db_service - $msg"

		echo "accessing the url $url..." >&2

		if [ "${arg_db_tls:-}" = 'true' ]; then
			output="$(curl --fail --silent --show-error \
					-u "elastic:$arg_db_pass" \
					--cacert "${arg_db_tls_ca_cert:-}" \
					"$url" \
				)"
		else
			output="$(curl --fail --silent --show-error "$url")"
		fi

		lines="$(echo "$output" | wc -l)"

		if [ -n "$output" ] && [[ "$lines" -ge 1 ]]; then
			echo "true"
		else
			echo "false"
		fi
		;;
	"db:main:elasticsearch:restore")
		"$pod_script_env_file" "db:main:elasticsearch:repository" ${args[@]+"${args[@]}"}

		es_args=()

		if [ "${arg_db_tls:-}" = 'true' ]; then
			db_pass="$("$inner_run_file" "db:main:elasticsearch:pass" ${args[@]+"${args[@]}"})"

			es_args+=( --user elastic )
			es_args+=( --password "$db_pass" )

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
	*)
		error "$command: invalid command"
		;;
esac
