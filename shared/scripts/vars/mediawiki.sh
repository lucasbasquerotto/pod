#!/bin/bash
set -eou pipefail

function tmp_error {
	echo "${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}" >&2
	exit 2
}

errors=()

errors+=("inicio ...")

export var_custom__pod_type="${var_load__pod_type:-}"
export var_custom__local="${var_load__local:-}"
export var_custom__use_main_network="${var_load__use_main_network:-}"
export var_custom__use_logrotator="${var_load__use_logrotator:-}"
export var_custom__use_nginx="${var_load__use_nginx:-}"
export var_custom__use_mysql="${var_load__use_mysql:-}"
export var_custom__use_fluentd="${var_load__use_fluentd:-}"
export var_custom__use_theia="${var_load__use_theia:-}"
export var_custom__use_varnish="${var_load__use_varnish:-}"
export var_custom__use_custom_ssl="${var_load__use_custom_ssl:-}"
export var_custom__use_certbot="${var_load__use_certbot:-}"

if [ -z "${var_load__data_dir:-}" ]; then
	errors+=("var_load__data_dir not defined")
fi

if [ "${var_load__local:-}" = 'true' ]; then
	export var_data_dir_rel="${var_load__data_dir:-}"
else
	export var_data_dir="${var_load__data_dir:-}"
fi

if [ -z "${var_load__pod_type:-}" ]; then
	errors+=("var_load__pod_type not defined")
fi

if [ -z "${var_load__migrate__db_name:-}" ]; then
	errors+=("var_load__migrate__db_name not defined")
fi

if [ -z "${var_load__migrate__db_user:-}" ]; then
	errors+=("var_load__migrate__db_user not defined")
fi

export var_run__migrate__db_service='mysql'
export var_run__migrate__db_name="${var_load__migrate__db_name:-}"
export var_run__migrate__db_user="${var_load__migrate__db_user:-}"
export var_run__migrate__db_pass="${var_load__migrate__db_pass:-}"
export var_run__migrate__db_connect_wait_secs="${var_load__migrate__db_connect_wait_secs:-300}"

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'web' ]; then
	if [ "${var_load__enable_backup_replica:-}" = 'true' ]; then
		if [ -z "${var_load__backup_replica_bucket_name:-}" ]; then
			errors+=("var_load__backup_replica_bucket_name not defined")
		fi

		export var_shared__s3_replicate_backup__bucket_dest_name="${var_load__backup_replica_bucket_name:-}"
		export var_shared__s3_replicate_backup__bucket_dest_path="${var_load__backup_replica_bucket_path:-}"
	fi

	if [ "${var_load__enable_uploads_replica:-}" = 'true' ]; then
		if [ -z "${var_load__uploads_replica_bucket_name:-}" ]; then
			errors+=("var_load__uploads_replica_bucket_name not defined")
		fi

		export var_shared__s3_replicate_uploads__bucket_dest_name="${var_load__uploads_replica_bucket_name:-}"
		export var_shared__s3_replicate_uploads__bucket_dest_path="${var_load__uploads_replica_bucket_path:-}"
	fi
fi

tmp_group_backup=""

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'db' ]; then
	if [ "${var_load__enable_db_backup:-}" = 'true' ]; then
		tmp_group_backup="$tmp_group_backup,db_backup"
	fi
fi

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'web' ]; then
	if [ "${var_load__enable_uploads_backup:-}" = 'true' ]; then
		tmp_group_backup="$tmp_group_backup,uploads_backup"
	fi
fi

if [ -n "$tmp_group_backup" ]; then
	tmp_group_backup="${tmp_group_backup:1}"
fi

export var_run__tasks__backup='group_backup'
export var_task__group_backup__task__type='group'
export var_task__group_backup__group_task__task_names="$tmp_group_backup"

tmp_group_setup=""

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'web' ]; then
	if [ "${var_load__enable_uploads_setup:-}" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,uploads_setup"
	fi
fi

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'db' ]; then
	if [ "${var_load__enable_db_setup:-}" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,db_setup"
	fi
fi

if [ -n "$tmp_group_setup" ]; then
	tmp_group_setup="${tmp_group_setup:1}"
fi

export var_run__tasks__setup='group_setup'
export var_task__group_setup__task__type='group'
export var_task__group_setup__group_task__task_names="$tmp_group_setup"

# Tasks

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'web' ]; then
	if [ "${var_load__block_ips:-}" = 'true' ]; then
		export var_shared__block_ips__action_exec__max_amount="${var_load__block_ips__max_amount:-10000}"
		export var_shared__block_ips__action_exec__amount_day="${var_load__block_ips__amount_day:-20000}"
		export var_shared__block_ips__action_exec__amount_hour="${var_load__block_ips__amount_hour:-3600}"

		export var_shared__s3_replicate_uploads__bucket_dest_name="${var_load__uploads_replica_bucket_name:-}"
		export var_shared__s3_replicate_uploads__bucket_dest_path="${var_load__uploads_replica_bucket_path:-}"
	fi
fi

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'web' ]; then
	if [ "${var_load__use_certbot:-}" = 'true' ]; then
		if [ -z "${var_load__certbot__main_domain:-}" ]; then
			errors+=("var_load__certbot__main_domain not defined")
		fi

		if [ -z "${var_load__certbot__domains:-}" ]; then
			errors+=("var_load__certbot__domains not defined")
		fi

		if [ -z "${var_load__certbot__email:-}" ]; then
			errors+=("var_load__certbot__email not defined")
		fi

		export var_task__certbot__task__type='certbot'
		export var_task__certbot__certbot_task__certbot_cmd='setup'
		export var_task__certbot__certbot_subtask__certbot_service='certbot'
		export var_task__certbot__certbot_subtask__toolbox_service='toolbox'
		export var_task__certbot__certbot_subtask__webservice_type='nginx'
		export var_task__certbot__certbot_subtask__data_base_path='/var/main/data/sync/certbot'

		export var_task__certbot__certbot_subtask__dev="${var_load__certbot__dev:-$var_custom__local}"
		export var_task__certbot__certbot_subtask__domains="${var_load__certbot__domains:-}"
		export var_task__certbot__certbot_subtask__email="${var_load__certbot__email:-}"
		export var_task__certbot__certbot_subtask__force="${var_load__certbot__force:-}"
		export var_task__certbot__certbot_subtask__main_domain="${var_load__certbot__main_domain:-}"
		export var_task__certbot__certbot_subtask__rsa_key_size="${var_load__certbot__rsa_key_size:-4096}"
		export var_task__certbot__certbot_subtask__staging="${var_load__certbot__staging:-$var_custom__local}"
	fi
fi

if [ "${var_load__pod_type:-}" = 'app' ] || [ "${var_load__pod_type:-}" = 'db' ]; then
	if [ "${var_load__enable_db_backup:-}" = 'true' ]; then
		tmp_db_src_dir='/tmp/main/tmp/mysql/backup'
		tmp_db_tmp_dir='/tmp/main/tmp/backup/mysql'

		export var_task__db_backup__task__type='backup'
		export var_task__db_backup__backup_task__subtask_cmd_local='backup:local:db'
		export var_task__db_backup__backup_task__subtask_cmd_remote='backup:remote:default'
		export var_task__db_backup__backup_task__is_compressed_file="${var_load__db_backup__is_compressed_file:-}"

		if [ "${var_task__db_backup__backup_task__is_compressed_file:-}" = 'true' ]; then
			tmp_default_compressed_file_name="${var_load__migrate__db_name:-}.[[ datetime ]].[[ random ]].zip"
			tmp_db_compressed_file_name="${var_load__db_backup__db_compressed_file_name:-$tmp_default_compressed_file_name}"

			export var_task__db_backup__backup_task__recursive_dir="$tmp_db_src_dir"
			export var_task__db_backup__backup_task__compress_type="${var_load__db_backup__db_compress_type:-zip}"
			export var_task__db_backup__backup_task__compress_dest_file="$tmp_db_tmp_dir/$tmp_db_compressed_file_name"
			export var_task__db_backup__backup_task__compress_pass="${var_load__db_backup__compress_pass:-}"
		else
			export var_task__db_backup__backup_task__recursive_dir="$tmp_db_tmp_dir"
		fi

		export var_task__db_backup__backup_task__backup_date_format="${var_load__db_backup__backup_date_format:-}"
		export var_task__db_backup__backup_task__backup_time_format="${var_load__db_backup__backup_time_format:-}"
		export var_task__db_backup__backup_task__backup_datetime_format="${var_load__db_backup__backup_datetime_format:-}"
		export var_task__db_backup__backup_task__recursive_mode="${var_load__db_backup__recursive_mode:-}"
		export var_task__db_backup__backup_task__recursive_mode_dir="${var_load__db_backup__recursive_mode_dir:-}"
		export var_task__db_backup__backup_task__recursive_mode_file="${var_load__db_backup__recursive_mode_file:-}"
		export var_task__db_backup__backup_task__file_to_clear="${var_load__db_backup__file_to_clear:-}"
		export var_task__db_backup__backup_task__dir_to_clear="${var_load__db_backup__dir_to_clear:-}"

		export var_task__db_backup__backup_local__task_name="db_main"
		export var_task__db_backup__backup_local__db_subtask_cmd='db:backup:file:mysql'
		export var_task__db_backup__backup_local__db_file_name="${var_load__migrate__db_name:-}.sql"
		export var_task__db_backup__backup_local__db_task_base_dir="$tmp_db_src_dir"

		tmp_default_sync_dir='[[ date ]]'

		export var_task__db_backup__backup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
		export var_task__db_backup__backup_remote__backup_bucket_sync_dir="${var_load__db_backup__backup_bucket_sync_dir:-$tmp_default_sync_dir}"
		export var_task__db_backup__backup_remote__backup_date_format="${var_load__db_backup__backup_date_format:-}"
		export var_task__db_backup__backup_remote__backup_time_format="${var_load__db_backup__backup_time_format:-}"
		export var_task__db_backup__backup_remote__backup_datetime_format="${var_load__db_backup__backup_datetime_format:-}"
	fi
fi

if [ -z "${var_load__db_main__db_name:-}" ]; then
	errors+=("var_load__db_main__db_name not defined")
fi

if [ -z "${var_load__db_main__db_user:-}" ]; then
	errors+=("var_load__db_main__db_user not defined")
fi

export var_task__db_main__db_subtask__db_service='mysql'
export var_task__db_main__db_subtask__db_name="${var_load__db_main__db_name:-}"
export var_task__db_main__db_subtask__db_user="${var_load__db_main__db_user:-}"
export var_task__db_main__db_subtask__db_pass="${var_load__db_main__db_pass:-}"
export var_task__db_main__db_subtask__db_connect_wait_secs="${var_load__db_main__db_connect_wait_secs:-300}"

if [ "${var_load__log_summary__disabled:-}" = 'false' ]; then
    export var_custom__log_summary__days_ago="${var_load__log_summary__days_ago:-1}"
    export var_custom__log_summary__max_amount="${var_load__log_summary__max_amount:-100}"
    export var_custom__log_summary__verify_size_docker_dir="${var_load__log_summary__verify_size_docker_dir:-}"
    export var_custom__log_summary__verify_size_containers="${var_load__log_summary__verify_size_containers:-true}"
fi

errors+=("... fim")

# get length of an array
error_count=${#errors[@]}

if [[ $error_count -gt 0 ]]; then
	for (( i=1; i<${error_count}+1; i++ )); do
		echo "$i/${error_count}: ${errors[$i-1]}" >&2
	done

	tmp_error "$error_count error(s) when loading the variables"
fi