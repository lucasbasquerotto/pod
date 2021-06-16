#!/bin/bash
# shellcheck disable=SC2154
set -eou pipefail

pod_layer_dir="$var_pod_layer_dir"
pod_script_env_file="$var_pod_script"
pod_data_dir="$var_pod_data_dir"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env - shared)."
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
		task_name ) arg_task_name="${OPTARG:-}";;
		??* ) ;; ## ignore
		\? )  ;; ## ignore
	esac
done
shift $((OPTIND-1))

pod_main_run_file="$pod_layer_dir/main/scripts/main.sh"
pod_script_container_file="$pod_layer_dir/main/scripts/container.sh"

pod_script_db_file="$pod_layer_dir/shared/scripts/db.sh"
log_run_file="$pod_layer_dir/shared/scripts/log.sh"
pod_script_services_file="$pod_layer_dir/shared/scripts/services.sh"
test_run_file="$pod_layer_dir/shared/scripts/test.sh"

ssl_local_run_file="$pod_layer_dir/shared/scripts/lib/ssl.local.sh"

title="${arg_task_name:-}"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"
[ -n "${title:-}" ] && title="$title - "
title="${title}${command}"

next_args=( --task_name"${arg_task_name:-}" --subtask_cmd="$command" )

case "$command" in
	"build")
		"$pod_script_services_file" build
		"$pod_main_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"prepare"|"migrate")
		"$pod_script_services_file" "$command"
		;;
	"setup")
		if [ "${var_main__local:-}" = 'true' ]; then
			"$pod_script_env_file" "action:exec:setup" ${next_args[@]+"${next_args[@]}"}
		else
			"$pod_script_env_file" "shared:bg:setup" ${next_args[@]+"${next_args[@]}"}
		fi
		;;
	"action:exec:setup")
		"$pod_script_services_file" setup
		"$pod_script_env_file" "shared:setup"
		;;
	"shared:setup")
		"$pod_main_run_file" setup
		;;
	"local:ssl")
		host="${1:-}"
		"$ssl_local_run_file" "$pod_layer_dir/tmp/ssl" "$host"
		;;
	"local:clear")
		mapfile -t list < <(sudo docker ps -aq)
		[[ ${#list[@]} -gt 0 ]] && sudo docker container rm -f "${list[@]}"
		"$pod_script_env_file" down -v
		sudo docker container prune -f
		sudo docker network prune -f
		sudo rm -rf "$pod_data_dir"
		;;
	"local:clear-all")
		mapfile -t list < <(sudo docker ps -aq)
		[[ ${#list[@]} -gt 0 ]] && sudo docker container rm -f "${list[@]}"
		sudo docker container prune -f
		sudo docker network prune -f
		sudo docker volume prune -f

		data_dir_aux="$pod_data_dir/../../../data"

		if [ -d "$data_dir_aux" ]; then
			data_dir="$(cd "$data_dir_aux" && pwd)"
			sudo rm -rf "$data_dir/"*
		fi
		;;
	"local:clear-remote")
		if [ "${var_main__use_s3:-}" = 'true' ]; then
			if [ "${var_run__enable__main_backup:-}" = 'true' ]; then
				"$pod_script_env_file" "s3:subtask:s3_backup" --s3_cmd=rb
			fi

			if [ "${var_run__enable__backup_replica:-}" = 'true' ]; then
				"$pod_script_env_file" "s3:subtask:s3_backup_replica" --s3_cmd=rb
			fi

			if [ "${var_run__enable__uploads_backup:-}" = 'true' ]; then
				"$pod_script_env_file" "s3:subtask:s3_uploads" --s3_cmd=rb
			fi

			if [ "${var_run__enable__uploads_replica:-}" = 'true' ]; then
				"$pod_script_env_file" "s3:subtask:s3_uploads_replica" --s3_cmd=rb
			fi
		fi
		;;
	"backup"|"local.backup")
		"$pod_script_env_file" "shared:bg:$command" ${next_args[@]+"${next_args[@]}"}
		;;
	"action:exec:backup"|"action:exec:local.backup")
		task_name="${command#action:exec:}"

		if [ "${var_main__use_logrotator:-}" = 'true' ]; then
			"$pod_script_env_file" "unique:action:logrotate" ${next_args[@]+"${next_args[@]}"} ||:
		fi

		"$pod_main_run_file" "$task_name" ${next_args[@]+"${next_args[@]}"}
		;;
	"shared:bg:"*)
		task_name="${command#shared:bg:}"

		"$pod_script_env_file" "bg:subtask" \
			--task_name="$title >> $task_name" \
			--task_name="$task_name" \
			--subtask_cmd="$command" \
			--bg_file="$pod_data_dir/log/bg/$task_name.$(date -u '+%Y%m%d.%H%M%S').$$.log" \
			--action_dir="/var/main/data/action"
		;;
	"action:exec:watch")
		"$pod_script_env_file" "action:exec:pending"

		inotifywait -m "$pod_data_dir/action" -e create -e moved_to |
			while read -r _ _ file; do
				if [[ $file != *.running ]] && [[ $file != *.error ]] && [[ $file != *.done ]]; then
					"$pod_script_env_file" "action:exec:pending"
					echo "waiting next action..."
				fi
			done
		;;
	"action:exec:pending")
		amount=1

		while [ "$amount" -gt 0 ]; do
			amount=0

			find "$pod_data_dir/action" -maxdepth 1 | while read -r file; do
				if [ -f "$file" ] && [[ $file != *.running ]] && [[ $file != *.error ]] && [[ $file != *.done ]]; then
					filename="$(basename "$file")"
					amount=$(( amount + 1 ))

					"$pod_script_env_file" "shared:action:$filename" \
						|| error "$title: error when running action $filename" ||:

					sleep 1
				fi
			done
		done
		;;
	"shared:action:"*)
		task_name="${command#shared:action:}"

		opts=()

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=toolbox" )
		opts+=( "--action_dir=/var/main/data/action" )

		"$pod_main_run_file" "action:subtask" "${opts[@]}"
		;;
	"shared:create_actions")
		info "$command - create the following actions: ${args[*]}"
		for action in "${args[@]}"; do
			echo "touch '/var/main/data/action/$action'"
		done | "$pod_script_env_file" exec-nontty toolbox /bin/bash
		;;
	"action:exec:logrotate")
		"$pod_script_env_file" run logrotator
		;;
	"action:exec:log_register."*)
		task_name="${command#action:exec:log_register.}"
		"$pod_script_env_file" "shared:log:register:$task_name" \
			${next_args[@]+"${next_args[@]}"}
		;;
	"action:exec:replicate_s3")
		if [ "${var_run__enable__backup_replica:-}" = 'true' ]; then
			"$pod_script_env_file" "shared:s3:replicate:backup"
		fi

		if [ "${var_run__enable__uploads_replica:-}" = 'true' ]; then
			"$pod_script_env_file" "shared:s3:replicate:uploads"
		fi
		;;
	"action:exec:nginx_reload")
		"$pod_script_env_file" "service:nginx:reload" ${args[@]+"${args[@]}"}
		;;
	"action:exec:haproxy_reload")
		"$pod_script_env_file" "service:haproxy:reload" ${args[@]+"${args[@]}"}
		;;
	"action:exec:block_ips")
		"$pod_script_services_file" block_ips ${args[@]+"${args[@]}"}
		;;
	"shared:create_secrets")
		"$pod_script_env_file" "util:values_to_files" \
			--task_info="$title" \
			--src_file="$pod_layer_dir/env/secrets.txt" \
			--dest_dir="$pod_data_dir/secrets" \
			--file_extension=".txt" \
			--remove_empty_values=''
		;;
	"shared:setup:main:network")
		default_name="${var_run__general__ctx_full_name}-network"
		network_name="${var_run__general__shared_network:-$default_name}"
		network_result="$("$pod_script_container_file" network ls --format "{{.Name}}" | grep "^${network_name}$" ||:)"

		if [ -z "$network_result" ]; then
			>&2 info "$command - creating the network $network_name..."
			"$pod_script_container_file" network create -d bridge "$network_name"
		fi
		;;
	"shared:setup:prepare:s3")
		if [ "${var_run__general__define_s3_backup_lifecycle:-}" = 'true' ]; then
			cmd="s3:subtask:s3_backup"
			info "$command - $cmd - define the backup bucket lifecycle policy"
			>&2 "$pod_script_env_file" "$cmd" --s3_cmd=lifecycle --task_info="$title"
		fi

		if [ "${var_run__general__define_s3_uploads_lifecycle:-}" = 'true' ]; then
			cmd="s3:subtask:s3_uploads"
			info "$command - $cmd - define the uploads bucket lifecycle policy"
			>&2 "$pod_script_env_file" "$cmd" --s3_cmd=lifecycle --task_info="$title"
		fi
		;;
	"setup:verify:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_verify"
		;;
	"setup:local:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_local"
		;;
	"setup:remote:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_remote"
		;;
	"setup:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="setup_db"
		;;
	"backup:local:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_local"
		;;
	"backup:remote:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_remote"
		;;
	"backup:db")
		"$pod_script_env_file" "db:common" \
			--task_info="$title" \
			--task_name="$arg_task_name" \
			--db_common_prefix="backup_db"
		;;
	"db:common"|"db:task:"*|"db:subtask:"*|"db:subtask"|"db:main:"*)
		"$pod_script_db_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"shared:outer_proxy"|"local:shared:outer_proxy")
		"$pod_script_services_file" outer_proxy ${args[@]+"${args[@]}"}
		;;
	"shared:s3:replicate:backup")
		task_name='s3_backup_replica'

		opts=()

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--s3_cmd=sync" )

		opts+=( "--s3_src_alias=backup" )
		opts+=( "--s3_remote_src=true" )
		opts+=( "--s3_bucket_src_name=$var_task__s3_backup__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_src_path=${var_task__s3_backup__s3_subtask__bucket_path:-}" )

		opts+=( "--s3_dest_alias=backup_replica" )
		opts+=( "--s3_remote_dest=true" )
		opts+=( "--s3_bucket_dest_name=$var_task__s3_backup_replica__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_dest_path=${var_task__s3_backup_replica__s3_subtask__bucket_path:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"shared:s3:replicate:uploads")
		task_name='s3_uploads_replica'

		opts=()

		opts=( "--task_info=$title >> $task_name" )

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--s3_cmd=sync" )

		opts+=( "--s3_src_alias=uploads" )
		opts+=( "--s3_remote_src=true" )
		opts+=( "--s3_bucket_src_name=$var_task__s3_uploads__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_src_path=${var_task__s3_uploads__s3_subtask__bucket_path:-}" )

		opts+=( "--s3_dest_alias=uploads_replica" )
		opts+=( "--s3_remote_dest=true" )
		opts+=( "--s3_bucket_dest_name=$var_task__s3_uploads_replica__s3_subtask__bucket_name" )
		opts+=( "--s3_bucket_dest_path=${var_task__s3_uploads_replica__s3_subtask__bucket_path:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"delete:old")
		info "$command - clear old files"
		>&2 "$pod_script_env_file" up toolbox

		dirs=( "/var/log/main/" "/tmp/main/tmp/" )

		re_number='^[0-9]+$'
		delete_old_days="${var_shared__delete_old__days:-7}"

		if ! [[ $delete_old_days =~ $re_number ]] ; then
			msg="The variable 'var_shared__delete_old__days' should be a number"
			error "$title: $msg (value=$delete_old_days)"
		fi

		info "$command - create the backup base directory and clear old files"
		"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL || error "$title"
			set -eou pipefail

			for dir in "${dirs[@]}"; do
				if [ -d "\$dir" ]; then
					# remove old files and directories
					find "\$dir" -mindepth 1 -ctime +$delete_old_days -delete -print;

					# remove old and empty directories
					find "\$dir" -mindepth 1 -type d -ctime +$delete_old_days -empty -delete -print;
				fi
			done
		SHELL
		;;
	"service:"*|"shared:service:"*)
		"$pod_script_services_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"shared:log:"*)
		"$log_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"shared:test:"*)
		"$test_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	*)
		"$pod_main_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
esac
