#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

pod_layer_dir="$var_pod_layer_dir"
pod_script_env_file="$var_pod_script"
pod_data_dir="$var_pod_data_dir"

cloudflare_run_file="$pod_layer_dir/shared/scripts/services/cloudflare.sh"
cron_run_file="$pod_layer_dir/shared/scripts/services/cron.sh"
haproxy_run_file="$pod_layer_dir/shared/scripts/services/haproxy.sh"
mysql_run_file="$pod_layer_dir/shared/scripts/services/mysql.sh"
nextcloud_run_file="$pod_layer_dir/shared/scripts/services/nextcloud.sh"
nginx_run_file="$pod_layer_dir/shared/scripts/services/nginx.sh"
redis_run_file="$pod_layer_dir/shared/scripts/services/redis.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit $LINENO;' ERR

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
		task_info ) arg_task_info="${OPTARG:-}" ;;
		force ) arg_force="${OPTARG:-}"; [ -z "${OPTARG:-}" ] && arg_force='true';;
		max_amount ) arg_max_amount="${OPTARG:-}";;
		only_if_needed )
			arg_only_if_needed="${OPTARG:-}";
			[ -z "${OPTARG:-}" ] && arg_only_if_needed='true'
			;;
		??* )  ;; ## ignore
		\? )  ;; ## ignore
	esac
done
shift $((OPTIND-1))

title=''
[ -n "${arg_task_info:-}" ] && title="${arg_task_info:-} > "
title="${title}${command}"

case "$command" in
	"before:upgrade")
		"$pod_script_env_file" "main:inner:vars"

		if [ "${var_main__use_secrets:-}" = 'true' ]; then
			"$pod_script_env_file" "shared:create_secrets"
		fi

		if [ "${var_main__use_main_network:-}" = 'true' ]; then
			"$pod_script_env_file" "shared:setup:main:network" ${next_args[@]+"${next_args[@]}"}
		fi

		if [ -n "${var_run__general__s3_cli:-}" ]; then
			env_dir_s3_cli="$pod_layer_dir/env/$var_run__general__s3_cli"

			dir="${env_dir_s3_cli}/etc"

			if [ ! -d "$dir" ]; then
				mkdir -p "$dir"
			fi
		fi

		if [ "${var_main__use_nginx:-}" = 'true' ]; then
			if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "web" ]; then
				env_dir_nginx="$pod_layer_dir/env/nginx"

				dir="${env_dir_nginx}/auth"

				if [ ! -d "$dir" ]; then
					mkdir -p "$dir"
				fi

				dir="${env_dir_nginx}/www"

				if [ ! -d "$dir" ]; then
					mkdir -p "$dir"
				fi
			fi
		fi

		if [ "${var_main__use_internal_fluentd:-}" = 'true' ]; then
			if [ "${var_shared__fluentd_output_plugin:-}" = 'file' ]; then
				src_file="$pod_layer_dir/shared/containers/fluentd/file.conf"
				dest_dir="$pod_layer_dir/env/fluentd"

				if [ ! -d "$dest_dir" ]; then
					mkdir -p "$dest_dir"
				fi

				cp "$src_file" "$dest_dir/fluent.conf"
			fi
		fi

		if [ -n "${var_run__general__main_base_dir:-}" ] \
				&& [ -n "${var_run__general__main_base_dir_container:-}" ] \
				&& [ "${var_run__general__main_base_dir:-}" != "${var_run__general__main_base_dir_container:-}" ]; then

			src_dir="$(readlink -f "$pod_layer_dir/$var_run__general__main_base_dir")"
			dest_dir="$pod_layer_dir/$var_run__general__main_base_dir_container"

			mkdir -p "$dest_dir"
			rsync --recursive --delete --exclude "/" "$src_dir/" "$dest_dir/"
		fi
		;;
	"prepare")
		data_dir="/var/main/data"

		"$pod_script_env_file" up toolbox

		use_wale=''

		if [ "${var_main__use_wale:-}" = 'true' ] || [ "${var_main__use_wale_restore:-}" = 'true' ]; then
			use_wale='true'
		fi

		if [ "$use_wale" = 'true' ]; then
			"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL || error "$title"
				set -eou pipefail

				if [ "$use_wale" = 'true' ]; then
					dir="$data_dir/tmp/wale/env"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
					fi

					chmod 777 "\$dir"
				fi
			SHELL

			"$pod_script_env_file" "util:values_to_files" \
				--task_info="$title" \
				--src_file="$pod_layer_dir/env/postgres/wale.conf" \
				--dest_dir="$pod_data_dir/tmp/wale/env" \
				--file_extension="" \
				--remove_empty_values='true'
		fi

		"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL || error "$title"
			set -eou pipefail

			if [ "$use_wale" = 'true' ]; then
				dir="$data_dir/wale"

				if [ ! -d "\$dir" ]; then
					mkdir -p "\$dir"
				fi

				cp -r "$data_dir/tmp/wale/env/." "\$dir/"
				chown -R 70:70 "\$dir"
			fi

			dir="$data_dir/sync"

			if [ ! -d "\$dir" ]; then
				mkdir -p "\$dir"
			fi

			dir="$data_dir/log/bg"

			if [ ! -d "\$dir" ]; then
				mkdir -p "\$dir"
				chmod 777 "\$dir"
			fi

			if [ "${var_main__use_nginx:-}" = 'true' ]; then
				if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "web" ]; then
					dir_nginx="$data_dir/sync/nginx"

					dir="\${dir_nginx}/auto"
					file="\${dir}/ips-blacklist-auto.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1 1;
							# 1.2.3.4/16 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/ips-blacklist.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1 1;
							# 0.0.0.0/0 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/ua-blacklist.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# ~(Mozilla|Chrome) 1;
							# "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Safari/537.36" 1;
							# "python-requests/2.18.4" 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/allowed-hosts.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# *.googlebot.com
							# *.google.com
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/log-exclude-paths.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# theia.localhost
							# /app/uploads/
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/log-exclude-paths-full.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# theia.localhost
							# /app/uploads/
						EOF
					fi
				fi
			fi

			if [ "${var_main__use_haproxy:-}" = 'true' ]; then
				if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "web" ]; then
					dir_haproxy="$data_dir/sync/haproxy"

					dir="\${dir_haproxy}/auto"
					file="\${dir}/ips-blacklist-auto.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1
							# 1.2.3.4/16
						EOF
					fi

					dir="\${dir_haproxy}/manual"
					file="\${dir}/ips-blacklist.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1
							# 0.0.0.0/0
						EOF
					fi

					dir="\${dir_haproxy}/manual"
					file="\${dir}/ua-blacklist.lst"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Safari/537.36
							# python-requests/2.18.4
						EOF
					fi

					dir="\${dir_haproxy}/manual"
					file="\${dir}/allowed-hosts.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# *.googlebot.com
							# *.google.com
						EOF
					fi

					dir="\${dir_haproxy}/manual"
					file="\${dir}/log-exclude-paths.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# theia.localhost
							# /app/uploads/
						EOF
					fi

					dir="\${dir_haproxy}/manual"
					file="\${dir}/log-exclude-paths-full.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# theia.localhost
							# /app/uploads/
						EOF
					fi
				fi
			fi

			if [ "${var_main__use_mysql:-}" = 'true' ]; then
				if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "db" ]; then
					dir="$data_dir/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 755 "\$dir"
					fi

					dir="$data_dir/tmp/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 777 "\$dir"
					fi

					dir="$data_dir/tmp/log/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 777 "\$dir"
					fi
				fi
			fi

			if [ "${var_main__use_mongo:-}" = 'true' ]; then
				if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "db" ]; then
					dir="$data_dir/mongo/db"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 755 "\$dir"
					fi

					dir="$data_dir/mongo/dump"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 755 "\$dir"
					fi
				fi
			fi
		SHELL
		;;
	"setup")
		if [ "${var_main__use_theia:-}" = 'true' ]; then
			"$pod_script_env_file" up theia
		fi

		if [ "${var_main__use_s3_cli_main:-}" = 'true' ]; then
			"$pod_script_env_file" up s3_cli
		fi

		if [ "${var_main__use_local_s3:-}" = 'true' ]; then
			"$pod_script_env_file" up s3
		fi

		if [ "${var_main__use_outer_proxy:-}" = 'true' ]; then
			cmd="shared:outer_proxy"
			[ "${var_main__local:-}" = 'true' ] && cmd="local:shared:outer_proxy"
			"$pod_script_env_file" "$cmd" --only_if_needed
		fi

		if [ "${var_main__use_certbot:-}" = 'true' ]; then
			info "$command - run certbot if needed..."
			"$pod_script_env_file" "main:task:certbot" ${next_args[@]+"${next_args[@]}"}
		fi

		if [ "${var_main__use_nginx:-}" = 'true' ]; then
			"$pod_script_env_file" up nginx
			"$pod_script_env_file" "service:nginx:reload"
		fi

		if [ "${var_main__use_haproxy:-}" = 'true' ]; then
			"$pod_script_env_file" up haproxy
			"$pod_script_env_file" "service:haproxy:reload"
		fi

		if [ "${var_main__local:-}" = 'false' ]; then
			"$pod_script_env_file" "shared:s3:setup:prepare" --task_info="$title"
		fi

		if [ "${var_main__use_mongo:-}" = 'true' ]; then
			if [ "$var_main__pod_type" = "app" ] || [ "$var_main__pod_type" = "db" ]; then
				"$pod_script_env_file" up mongo

				info "$command - init the mongo database if needed"
				"$pod_script_env_file" run mongo_init /bin/bash <<-SHELL || error "$title"
					set -eou pipefail

					for i in \$(seq 1 30); do
						mongo mongo/"$var_run__migrate__db_name" \
							--authenticationDatabase admin \
							--username "$var_run__migrate__db_root_user" \
							--password "${var_run__migrate__db_root_pass:-}" \
							--eval "
								rs.initiate({
									_id: 'rs0',
									members: [ { _id: 0, host: 'localhost:27017' } ]
								})
							" && s=\$? && break || s=\$?;
						echo "Tried \$i times. Waiting 5 secs...";
						sleep 5;
					done;

					if [ "\$s" != "0" ]; then
						exit "\$s"
					fi

					for i in \$(seq 1 30); do
						mongo mongo/admin \
							--authenticationDatabase admin \
							--username "$var_run__migrate__db_root_user" \
							--password "${var_run__migrate__db_root_pass:-}" \
							/tmp/main/init.js && s=\$? && break || s=\$?;
						echo "Tried \$i times. Waiting 5 secs...";
						sleep 5;
					done;

					if [ "\$s" != "0" ]; then
						exit "\$s"
					fi
				SHELL
			fi
		fi
		;;
	"migrate")
		if [ "${var_main__use_varnish:-}" = 'true' ]; then
			"$pod_script_env_file" up varnish

			info "$command - clear varnish cache..."
			"$pod_script_env_file" "service:varnish:clear" ${next_args[@]+"${next_args[@]}"}
		fi

		if [ "${var_main__use_nextcloud:-}" = 'true' ]; then
			info "$command - prepare nextcloud..."
			"$pod_script_env_file" "shared:service:main:nextcloud:setup" \
				${next_args[@]+"${next_args[@]}"}
		fi

		if [ "${var_shared__define_cron:-}" = 'true' ] && [ "${var_main__local:-}" = 'false' ]; then
			"$pod_script_env_file" cron --task_info="$title"
		fi
		;;
	"block_ips")
		service="${var_shared__block_ips__action_exec__service:-}"

		if [ "${var_shared__block_ips__action_exec__enabled:-}" != 'true' ]; then
			error "$title: action is not enabled"
		elif [ -z "$service" ]; then
			error "$title: no service specified"
		fi

		"$pod_script_env_file" "shared:log:$service:verify"

		dest_last_day_file="$("$pod_script_env_file" "shared:log:$service:day" \
			--force="${arg_force:-}" \
			--days_ago="1" \
			--max_amount="${arg_max_amount:-}")"

		dest_day_file=""

		if [ "${var_shared__block_ips__action_exec__current_day:-}" = 'true' ]; then
			dest_day_file="$("$pod_script_env_file" "shared:log:$service:day" \
				--force="${arg_force:-}" \
				--max_amount="${arg_max_amount:-}")"
		fi

		service_sync_base_dir="/var/main/data/sync/$service"
		log_hour_path_prefix="$("$pod_script_env_file" "shared:log:$service:hour_path_prefix")"

		"$pod_script_env_file" "service:$service:block_ips" \
			--task_info="$title" \
			--max_amount="${var_shared__block_ips__action_exec__max_amount:-$arg_max_amount}" \
			--output_file="$service_sync_base_dir/auto/ips-blacklist-auto.conf" \
			--manual_file="$service_sync_base_dir/manual/ips-blacklist.conf" \
			--allowed_hosts_file="$service_sync_base_dir/manual/allowed-hosts.conf" \
			--log_file_last_day="$dest_last_day_file" \
			--log_file_day="$dest_day_file" \
			--amount_day="$var_shared__block_ips__action_exec__amount_day" \
			--log_file_hour="$log_hour_path_prefix.$(date -u '+%Y-%m-%d.%H').log" \
			--log_file_last_hour="$log_hour_path_prefix.$(date -u -d '1 hour ago' '+%Y-%m-%d.%H').log" \
			--amount_hour="$var_shared__block_ips__action_exec__amount_hour"
		;;
	"outer_proxy")
		if [ "${var_main__use_haproxy:-}" = 'true' ]; then
			service='haproxy'
			result_file_relpath="sync/$service/auto/ips-proxy.lst"
		elif [ "${var_main__use_nginx:-}" = 'true' ]; then
			service='nginx'
			result_file_relpath="sync/$service/auto/ips-proxy.conf"
		else
			error "$command: expected nginx service not defined"
		fi

		output_file_format="$service"
		service_param="$service"
		[ "${arg_only_if_needed:-}" = 'true' ] && service_param=''

		if [ "$command" = "local:shared:outer_proxy" ]; then
			output=''

			if [ "${var_main__use_haproxy:-}" = 'true' ]; then
				output='0.0.0.0/0'
			elif [ "${var_main__use_nginx:-}" = 'true' ]; then
				output='0.0.0.0/0 1;'
			fi

			"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL || error "$command"
				set -eou pipefail
				echo "$output" > "/var/main/data/$result_file_relpath"
			SHELL

			if [ -n "$service_param" ]; then
				"$pod_script_env_file" "service:$service_param:reload"
			fi
		else
			"$pod_script_env_file" "service:${var_main__outer_proxy_type:-}:ips" \
				--task_info="$title" \
				--output_file_format="$output_file_format" \
				--webservice="$service_param" \
				--only_if_needed="${arg_only_if_needed:-}" \
				--output_file_relpath="$result_file_relpath"
		fi
		;;
	"shared:service:main:nextcloud:setup")
		"$pod_script_env_file" "service:nextcloud:setup" \
			--task_info="$title >> nextcloud" \
			--task_name="nextcloud" \
			--subtask_cmd="$command" \
			--admin_user="$var_shared__nextcloud__setup__admin_user" \
			--admin_pass="$var_shared__nextcloud__setup__admin_pass" \
			--nextcloud_url="$var_shared__nextcloud__setup__url" \
			--nextcloud_domain="$var_shared__nextcloud__setup__domain" \
			--nextcloud_host="$var_shared__nextcloud__setup__host" \
			--nextcloud_protocol="$var_shared__nextcloud__setup__protocol"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_info="$title >> nextcloud_action" \
			--task_name="nextcloud_action" \
			--subtask_cmd="$command" \
			--mount_point="/action" \
			--datadir="/var/main/data/action"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_info="$title >> nextcloud_data" \
			--task_name="nextcloud_data" \
			--subtask_cmd="$command" \
			--mount_point="/data" \
			--datadir="/var/main/data"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_info="$title >> nextcloud_sync" \
			--task_name="nextcloud_sync" \
			--subtask_cmd="$command" \
			--mount_point="/sync" \
			--datadir="/var/main/data/sync"

		if [ "${var_shared__nextcloud__s3_backup__enable:-}" = 'true' ]; then
			"$pod_script_env_file" "service:nextcloud:s3" \
				--task_info="$title >> nextcloud_backup" \
				--task_name="nextcloud_backup" \
				--subtask_cmd="$command" \
				--mount_point="/backup" \
				--bucket="$var_shared__nextcloud__s3_backup__bucket" \
				--hostname="$var_shared__nextcloud__s3_backup__hostname" \
				--port="$var_shared__nextcloud__s3_backup__port" \
				--region="$var_shared__nextcloud__s3_backup__region" \
				--use_ssl="$var_shared__nextcloud__s3_backup__use_ssl" \
				--use_path_style="$var_shared__nextcloud__s3_backup__use_path_style" \
				--legacy_auth="$var_shared__nextcloud__s3_backup__legacy_auth"  \
				--key="$var_shared__nextcloud__s3_backup__access_key" \
				--secret="$var_shared__nextcloud__s3_backup__secret_key"
		fi

		if [ "${var_shared__nextcloud__s3_uploads__enable:-}" = 'true' ]; then
			"$pod_script_env_file" "service:nextcloud:s3" \
				--task_info="$title >> nextcloud_uploads" \
				--task_name="nextcloud_uploads" \
				--subtask_cmd="$command" \
				--mount_point="/uploads" \
				--bucket="$var_shared__nextcloud__s3_uploads__bucket" \
				--hostname="$var_shared__nextcloud__s3_uploads__hostname" \
				--port="$var_shared__nextcloud__s3_uploads__port" \
				--region="$var_shared__nextcloud__s3_uploads__region" \
				--use_ssl="$var_shared__nextcloud__s3_uploads__use_ssl" \
				--use_path_style="$var_shared__nextcloud__s3_uploads__use_path_style" \
				--legacy_auth="$var_shared__nextcloud__s3_uploads__legacy_auth"  \
				--key="$var_shared__nextcloud__s3_uploads__access_key" \
				--secret="$var_shared__nextcloud__s3_uploads__secret_key"
		fi
		;;
	"service:cron")
		"$cron_run_file" \
			--cron_src="$pod_layer_dir/${var_shared__cron__src:-}" \
			--cron_dest="${var_shared__cron__dest:-}" \
			--cron_tmp_dir="$pod_data_dir/tmp/cron"
		;;
	"service:cron:custom")
		"$cron_run_file" "${args[@]}"
		;;
	"service:cloudflare:"*|"inner:service:cloudflare:"*)
		"$cloudflare_run_file" "$command" \
			--toolbox_service="toolbox" \
			${args[@]+"${args[@]}"}
		;;
	"service:haproxy:"*|"inner:service:haproxy:"*)
		"$haproxy_run_file" "$command" \
			--toolbox_service="toolbox" \
			--haproxy_service="haproxy" \
			${args[@]+"${args[@]}"}
		;;
	"service:mysql:"*|"inner:service:mysql:"*)
		"$mysql_run_file" "$command" \
			--toolbox_service="toolbox" \
			${args[@]+"${args[@]}"}
		;;
	"service:nextcloud:"*|"inner:service:nextcloud:"*)
		"$nextcloud_run_file" "$command" \
			--toolbox_service="toolbox" \
			--nextcloud_service="nextcloud" \
			${args[@]+"${args[@]}"}
		;;
	"service:nginx:"*|"inner:service:nginx:"*)
		"$nginx_run_file" "$command" \
			--toolbox_service="toolbox" \
			--nginx_service="nginx" \
			${args[@]+"${args[@]}"}
		;;
	"service:redis:"*|"inner:service:redis:"*)
		"$redis_run_file" "$command" \
			--toolbox_service="toolbox" \
			--redis_service="redis" \
			${args[@]+"${args[@]}"}
		;;
	"service:varnish:clear")
		cmd=( "$pod_script_env_file" exec-nontty varnish varnishadm ban req.url '~' '.' )
		error="$({ "${cmd[@]}"; } 2>&1)" && status=0 || status=1

		# Sometimes varnish returns an autentication error when the container was just created
		if [ "$status" = 1 ] && [[ "$error" == *'Authentication required'* ]]; then
			echo "waiting for the varnish service to be ready..."
			sleep 30
			"${cmd[@]}"
		fi
		;;
	*)
		error "$title: Invalid command"
		;;
esac
