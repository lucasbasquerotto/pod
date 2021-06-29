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
	if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_info ) arg_task_info="${OPTARG:-}";;
		task_name ) arg_task_name="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		certbot_service ) arg_certbot_service="${OPTARG:-}";;
		webservice_service ) arg_webservice_service="${OPTARG:-}";;
		certbot_cmd ) arg_certbot_cmd="${OPTARG:-}";;
		data_base_path ) arg_data_base_path="${OPTARG:-}";;
		main_domain ) arg_main_domain="${OPTARG:-}";;
		domains ) arg_domains="${OPTARG:-}";;
		rsa_key_size ) arg_rsa_key_size="${OPTARG:-}";;
		email ) arg_email="${OPTARG:-}";;
		dev ) arg_dev="${OPTARG:-}";;
		dev_renew_days ) arg_dev_renew_days="${OPTARG:-}";;
		staging ) arg_staging="${OPTARG:-}";;
		force ) arg_force="${OPTARG:-}"; [ -z "${OPTARG:-}" ] && arg_force='true';;
		data_path ) arg_data_path="${OPTARG:-}";;
		data_dir_done ) arg_data_dir_done="${OPTARG:-}";;
		data_file_done ) arg_data_file_done="${OPTARG:-}";;
		done ) arg_done="${OPTARG:-}";;
		local|subtask_cmd ) ;;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"certbot:task:"*)
		task_name="${command#certbot:task:}"
		prefix="var_task__${task_name}__certbot_task_"

		param_certbot_cmd="${prefix}_certbot_cmd"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=${!param_certbot_cmd}" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask:"*)
		task_name="${command#certbot:subtask:}"

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=$arg_certbot_cmd" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask")
		prefix="var_task__${arg_task_name}__certbot_subtask_"

		param_toolbox_service="${prefix}_toolbox_service"
		param_certbot_service="${prefix}_certbot_service"
		param_webservice_service="${prefix}_webservice_service"
		param_webservice_type="${prefix}_webservice_type"
		param_data_base_path="${prefix}_data_base_path"
		param_main_domain="${prefix}_main_domain"
		param_domains="${prefix}_domains"
		param_rsa_key_size="${prefix}_rsa_key_size"
		param_email="${prefix}_email"
		param_dev="${prefix}_dev"
		param_dev_renew_days="${prefix}_dev_renew_days"
		param_staging="${prefix}_staging"
		param_force="${prefix}_force"

		webservice_type_value="${!param_webservice_type}"

		opts=( "--task_info=$title" )

		opts+=( "--toolbox_service=${!param_toolbox_service}" )
		opts+=( "--certbot_service=${!param_certbot_service}" )
		opts+=( "--data_base_path=${!param_data_base_path}" )
		opts+=( "--main_domain=${!param_main_domain}" )
		opts+=( "--domains=${!param_domains}" )
		opts+=( "--rsa_key_size=${!param_rsa_key_size}" )
		opts+=( "--email=${!param_email}" )

		opts+=( "--webservice_service=${!param_webservice_service:-$webservice_type_value}" )
		opts+=( "--dev=${!param_dev:-}" )
		opts+=( "--dev_renew_days=${!param_dev_renew_days:-}" )
		opts+=( "--staging=${!param_staging:-}" )
		opts+=( "--force=${!param_force:-}" )

		"$pod_script_env_file" "service:certbot:$arg_certbot_cmd" "${opts[@]}"
		;;
	"service:certbot:setup")
		data_dir_done="$arg_data_base_path/tmp/$arg_main_domain"
		data_file_done="$data_dir_done/done.txt"

		data_path="$arg_data_base_path/etc"
		inner_path_base="/etc/letsencrypt"

		new_args=( ${args[@]+"${args[@]}"} )
		new_args+=( "--data_path=$data_path" )
		new_args+=( "--data_dir_done=$data_dir_done" )
		new_args+=( "--data_file_done=$data_file_done" )

		"$pod_script_env_file" up "$arg_toolbox_service"

		result="$(
			"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				bash "$inner_run_file" "inner:service:certbot:setup:prepare" "${new_args[@]}")"

		if [ -n "$result" ]; then
			if [ "$result" != 'exit' ]; then
				error "$title: [Error] Unknown result from the certbot preparation step (result=$result)"
			fi

			exit
		fi

		if [ -z "${arg_email:-}" ]; then
			error "$title: [Error] Specify an email to generate a TLS certificate"
		fi

		dummy_certificate_days="1"
		[ "${arg_dev:-}" = "true" ] && dummy_certificate_days="10000"

		info "$command: Preparing the directory $arg_main_domain ..."

		>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			mkdir -p "$data_path/live/$arg_main_domain"

		info "$command: Creating dummy certificate for $arg_main_domain ..."

		inner_path="$inner_path_base/live/$arg_main_domain"
		>&2 "$pod_script_env_file" run --entrypoint "\
			openssl req -x509 -nodes -newkey rsa:1024 -days $dummy_certificate_days\
				-keyout '$inner_path/privkey.pem' \
				-out '$inner_path/fullchain.pem' \
				-subj '/CN=localhost'" "$arg_certbot_service"

		info "$command: Creating dummy concatenated certificate for $arg_main_domain ..."
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:service:certbot:setup:after" "${new_args[@]}"

		info "$command: Starting $arg_webservice_service ..."
		>&2 "$pod_script_env_file" "service:certbot:ws:start" \
			--webservice_service="$arg_webservice_service"

		if [ "${arg_dev:-}" != "true" ]; then
			info "$command: Deleting dummy certificate for $arg_main_domain ..."
			>&2 "$pod_script_env_file" run --entrypoint "\
				rm -Rf $inner_path_base/live/$arg_main_domain && \
				rm -Rf $inner_path_base/archive/$arg_main_domain && \
				rm -Rf $inner_path_base/renewal/$arg_main_domain.conf" "$arg_certbot_service"

			info "$command: Requesting Let's Encrypt certificate for $arg_main_domain ..."
			# Join each domain to -d args
			IFS=' ' read -r -a domains_array <<< "$arg_domains"
			domain_args=""
			for domain in "${domains_array[@]}"; do
				domain_args="$domain_args -d '$domain'"
			done

			email_arg="--email $arg_email"
			staging_arg=""

			# Enable staging mode if needed
			if [ "${arg_staging:-}" != "false" ]; then staging_arg="--staging"; fi

			>&2 "$pod_script_env_file" run --entrypoint "\
				certbot certonly --webroot \
					-w /var/www/certbot \
					--cert-name '$arg_main_domain' \
					$staging_arg \
					$email_arg \
					$domain_args \
					--rsa-key-size $arg_rsa_key_size \
					--agree-tos \
					--force-renewal \
					--non-interactive" "$arg_certbot_service"
		fi

		new_args+=( "--done=true" )

		info "$command: Creating concatenated certificate for $arg_main_domain and marking as done ..."
		"$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
			bash "$inner_run_file" "inner:service:certbot:setup:after" "${new_args[@]}"

		if [ "${arg_dev:-}" != "true" ]; then
			info "$command: Reloading $arg_webservice_service ..."
			>&2 "$pod_script_env_file" "service:certbot:ws:reload" \
				--webservice_service="$arg_webservice_service"
		fi
		;;
	"inner:service:certbot:setup:prepare")
		if [ "${arg_dev:-}" = "true" ]; then
			info "$command: Preparing the development certificate environment ..."

			if [ -f "$arg_data_file_done" ]; then
				if [[ $(find "$arg_data_file_done" -mtime "+${arg_dev_renew_days:-7}" -print) ]]; then
					rm -f "$arg_data_file_done" >&2
				fi
			fi
		fi

		if [ "${arg_force:-}" != "true" ]; then
			has_file="$(test -f "$arg_data_file_done" >&2 && echo "true" || echo "false")"

			if [ "$has_file" != "false" ]; then
				if [ "$has_file" != "true" ]; then
					msg_aux="existence of file $arg_data_file_done is not known"
					error "$title: couldn't determine if certificate was already generated or not ($msg_aux)"
				fi

				info "$command: Certificate already generated (delete the file $arg_data_file_done to generate again)"
				echo "exit"
			fi
		fi
		;;
	"inner:service:certbot:setup:after")
		fullchain="$arg_data_path/live/$arg_main_domain/fullchain.pem"
		privkey="$arg_data_path/live/$arg_main_domain/privkey.pem"
		concat="$arg_data_path/live/$arg_main_domain/concat.pem"

		if [ -f "$fullchain" ] && [ -f "$privkey" ]; then
			cat "$fullchain" "$privkey" > "$concat"
		fi

		if [ "${arg_done:-}" = 'true' ]; then
			mkdir -p "$arg_data_dir_done"
			date '+%F %T' >> "$arg_data_file_done"
		fi
		;;
	"service:certbot:renew")
		data_dir_done="$arg_data_base_path/tmp/$arg_main_domain"
		data_file_done="$data_dir_done/done.txt"

		info "$command: Renewing the certificate for $arg_main_domain ..."
		>&2 "$pod_script_env_file" run \
			--entrypoint "certbot renew --cert-name '$arg_main_domain' --force-renewal" \
			"$arg_certbot_service"

		info "$command: Reloading $arg_webservice_service ..."
		>&2 "$pod_script_env_file" "service:certbot:ws:reload" \
			--webservice_service="$arg_webservice_service"
		;;
	"service:certbot:ws:start")
		>&2 "$pod_script_env_file" up "$arg_webservice_service"
		;;
	"service:certbot:ws:reload")
		>&2 "$pod_script_env_file" "service:$arg_webservice_service:reload" \
			--task_info="$title"
		;;
	*)
		error "$title: invalid command"
		;;
esac