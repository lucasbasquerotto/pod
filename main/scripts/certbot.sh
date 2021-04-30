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
		certbot_service ) arg_certbot_service="${OPTARG:-}";;
		webservice_service ) arg_webservice_service="${OPTARG:-}";;
		data_base_path ) arg_data_base_path="${OPTARG:-}";;
		main_domain ) arg_main_domain="${OPTARG:-}";;
		domains ) arg_domains="${OPTARG:-}";;
		rsa_key_size ) arg_rsa_key_size="${OPTARG:-}";;
		email ) arg_email="${OPTARG:-}";;
		dev ) arg_dev="${OPTARG:-}";;
		dev_renew_days ) arg_dev_renew_days="${OPTARG:-}";;
		staging ) arg_staging="${OPTARG:-}";;
		force ) arg_force="${OPTARG:-}"; [ -z "${OPTARG:-}" ] && arg_force='true';;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"certbot:setup")
		data_dir_done="$arg_data_base_path/tmp/$arg_main_domain"
		data_file_done="$data_dir_done/done.txt"

		data_path="$arg_data_base_path/etc"
		inner_path_base="/etc/letsencrypt"
		dummy_certificate_days="1"

		"$pod_script_env_file" up "$arg_toolbox_service"

		if [ "${arg_dev:-}" = "true" ]; then
			dummy_certificate_days="10000"

			info "$command: Preparing the development certificate environment ..."
			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$title"
				set -eou pipefail

				if [ -f "$data_file_done" ]; then
					if [[ \$(find "$data_file_done" -mtime "+${arg_dev_renew_days:-7}" -print) ]]; then
						rm -f "$data_file_done"
					fi
				fi
			SHELL
		fi

		if [ "${arg_force:-}" != "true" ]; then
			has_file="$("$pod_script_env_file" exec-nontty "$arg_toolbox_service" \
				test -f "$data_file_done" && echo "true" || echo "false")"

			if [ "$has_file" != "false" ]; then
				info "$command: Certificate already generated (delete the file $data_file_done to generate again)"
				exit
			fi
		fi

		if [ -z "${arg_email:-}" ]; then
			error "$title: [Error] Specify an email to generate a TLS certificate"
		fi

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
		>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$title"
			set -eou pipefail

			fullchain="$data_path/live/$arg_main_domain/fullchain.pem"
			privkey="$data_path/live/$arg_main_domain/privkey.pem"
			concat="$data_path/live/$arg_main_domain/concat.pem"

			if [ -f "\$fullchain" ] && [ -f "\$privkey" ]; then
				cat "\$fullchain" "\$privkey" > "\$concat"
			fi
		SHELL

		info "$command: Starting $arg_webservice_service ..."
		>&2 "$pod_script_env_file" "run:certbot:ws:start" \
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

		>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL || error "$title"
			set -eou pipefail

			fullchain="$data_path/live/$arg_main_domain/fullchain.pem"
			privkey="$data_path/live/$arg_main_domain/privkey.pem"
			concat="$data_path/live/$arg_main_domain/concat.pem"

			if [ -f "\$fullchain" ] && [ -f "\$privkey" ]; then
				cat "\$fullchain" "\$privkey" > "\$concat"
			fi

			mkdir -p "$data_dir_done"
			echo "$(date '+%F %T')" >> "$data_file_done"
		SHELL

		if [ "${arg_dev:-}" != "true" ]; then
			info "$command: Reloading $arg_webservice_service ..."
			>&2 "$pod_script_env_file" "run:certbot:ws:reload" \
				--webservice_service="$arg_webservice_service"
		fi
		;;
	"certbot:renew")
		data_dir_done="$arg_data_base_path/tmp/$arg_main_domain"
		data_file_done="$data_dir_done/done.txt"

		info "$command: Renewing the certificate for $arg_main_domain ..."
		>&2 "$pod_script_env_file" run \
			--entrypoint "certbot renew --cert-name '$arg_main_domain' --force-renewal" \
			"$arg_certbot_service"

		info "$command: Reloading $arg_webservice_service ..."
		>&2 "$pod_script_env_file" "run:certbot:ws:reload" \
			--webservice_service="$arg_webservice_service"
		;;
	"certbot:ws:start")
		>&2 "$pod_script_env_file" up "$arg_webservice_service"
		;;
	"certbot:ws:reload")
		>&2 "$pod_script_env_file" "service:$arg_webservice_service:reload" \
			--task_info="$title"
		;;
	*)
		error "$title: invalid command"
		;;
esac