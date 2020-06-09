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

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		certbot_service ) arg_certbot_service="${OPTARG:-}";;
		webservice_type ) arg_webservice_type="${OPTARG:-}";;
		webservice_service ) arg_webservice_service="${OPTARG:-}";;
		data_base_path ) arg_data_base_path="${OPTARG:-}";;
		main_domain ) arg_main_domain="${OPTARG:-}";;
		domains ) arg_domains="${OPTARG:-}";;
		rsa_key_size ) arg_rsa_key_size="${OPTARG:-}";;
		email ) arg_email="${OPTARG:-}";;
		dev ) arg_dev="${OPTARG:-}";;
		staging ) arg_staging="${OPTARG:-}";;
		force ) arg_force="${OPTARG:-}";;
		??* ) error "$command: Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

data_dir_done="$arg_data_base_path/tmp/$arg_main_domain"
data_file_done="$data_dir_done/done.txt"

case "$command" in
	"certbot:setup")
		data_path="$arg_data_base_path/etc"
		inner_path_base="/etc/letsencrypt"
		dummy_certificate_days="1"

		if [ "${arg_dev:-}" = "true" ]; then
			dummy_certificate_days="10000"
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
			error "$command: [Error] Specify an email to generate a TLS certificate"
		fi

		info "$command: Creating dummy certificate for $arg_main_domain ..."

		>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" mkdir -p "$data_path/live/$arg_main_domain"

		inner_path="$inner_path_base/live/$arg_main_domain"
		>&2 "$pod_script_env_file" run --rm --entrypoint "\
			openssl req -x509 -nodes -newkey rsa:1024 -days $dummy_certificate_days\
				-keyout '$inner_path/privkey.pem' \
				-out '$inner_path/fullchain.pem' \
				-subj '/CN=localhost'" "$arg_certbot_service"

		info "$command: Starting $arg_webservice_type ..."
		>&2 "$pod_script_env_file" "run:certbot:ws:start:$arg_webservice_type"

		if [ "${arg_dev:-}" != "true" ]; then
			info "$command: Deleting dummy certificate for $arg_main_domain ..."
			>&2 "$pod_script_env_file" run --rm --entrypoint "\
				rm -Rf $inner_path_base/live/$arg_main_domain && \
				rm -Rf $inner_path_base/archive/$arg_main_domain && \
				rm -Rf $inner_path_base/renewal/$arg_main_domain.conf" "$arg_certbot_service"

			info "$command: Requesting Let's Encrypt certificate for $arg_main_domain ..."
			#Join each domain to -d args
			domain_args=""
			for domain in "${arg_domains[@]}"; do
				domain_args="$domain_args -d '$domain'"
			done

			email_arg="--email $arg_email"
			staging_arg=""

			# Enable staging mode if needed
			if [ "${arg_staging:-}" != "false" ]; then staging_arg="--staging"; fi

			>&2 "$pod_script_env_file" run --rm --entrypoint "\
				certbot certonly --webroot -w /var/www/certbot \
					$staging_arg \
					$email_arg \
					$domain_args \
					--rsa-key-size $arg_rsa_key_size \
					--agree-tos \
					--force-renewal \
					--non-interactive" "$arg_certbot_service"

			info "$command: Reloading $arg_webservice_type ..."
			>&2 "$pod_script_env_file" "run:certbot:ws:reload:$arg_webservice_type"

			>&2 "$pod_script_env_file" exec-nontty "$arg_toolbox_service" /bin/bash <<-SHELL
				set -eou pipefail
				mkdir -p "$data_dir_done"
				echo "$(date '+%F %T')" >> "$data_file_done"
			SHELL
		fi
		;;
	"certbot:renew")
		info "$command: Renewing the certificate for $main_domain ..."
		>&2 "$pod_script_env_file" run --rm --entrypoint "certbot renew --force-renewal" "$arg_certbot_service"

		info "$command: Reloading $arg_webservice_type ..."
		>&2 "$pod_script_env_file" "run:certbot:ws:reload:$arg_webservice_type"
		;;
	"certbot:ws:start:nginx")
		>&2 "$pod_script_env_file" up -d "$arg_webservice_service"
		>&2 "$pod_script_env_file" restart "$arg_webservice_service"
		;;
	"certbot:ws:reload:nginx")
		>&2 "$pod_script_env_file" exec-nontty "$arg_webservice_service" nginx -s reload
		;;
	*)
		error "$command: invalid command"
		;;
esac