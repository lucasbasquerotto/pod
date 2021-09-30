#!/bin/bash
set -eou pipefail

tmp_errors=()

# Validations

if [ -z "${var_pod_layer_dir:-}" ]; then
	tmp_errors+=("[shared] var_pod_layer_dir is not defined")
fi

if [ -z "${var_load_name:-}" ]; then
	tmp_errors+=("[shared] var_load_name is not defined")
fi

if [ -z "${var_load_general__script_dir:-}" ]; then
	tmp_errors+=("[shared] var_load_general__script_dir is not defined")
fi

if [ -z "${var_load_general__script_env_file:-}" ]; then
	tmp_errors+=("[shared] var_load_general__script_env_file is not defined")
fi

if [ -z "${var_load_main__data_dir:-}" ]; then
	tmp_errors+=("[shared] var_load_main__data_dir is not defined")
fi

if [ -z "${var_load_main__pod_type:-}" ]; then
	tmp_errors+=("[shared] var_load_main__pod_type is not defined")
fi

if [ -z "${var_load_main__instance_index:-}" ]; then
	tmp_errors+=("[shared] var_load_main__instance_index is not defined")
fi

# Directories

#shellcheck disable=SC2154
tmp_pod_layer_dir="${var_pod_layer_dir:-}"

tmp_base_dir="${var_load_general__script_dir:-}"
tmp_full_dir="$tmp_base_dir/${var_load_general__script_env_file:-}"
export var_pod_script="$tmp_full_dir"

if [ "${var_load_main__local:-}" = 'true' ]; then
	export var_data_dir_rel="${var_load_main__data_dir:-}"
else
	export var_data_dir="${var_load_main__data_dir:-}"
fi

export var_pod_tmp_dir="$tmp_pod_layer_dir/${var_tmp_dir:-tmp}"
export var_pod_data_dir="${var_data_dir:-}"

if [ -z "${data_dir:-}" ] && [ -n "${var_data_dir_rel:-}" ]; then
	export var_pod_data_dir="$tmp_pod_layer_dir/$var_data_dir_rel"
fi

export var_inner_scripts_dir="${var_load_main__inner_scripts_dir:-/var/main/scripts}"

# Database

if [ "${var_load_main__db_service:-}" != '' ] && [ "${var_load_main__allow_custom_db_service:-}" != 'true' ]; then
	tmp_info="db: ${var_load_main__allow_custom_db_service:-}"

	case "${var_load_main__db_service:-}" in
		'mysql')
			if [ -z "${var_load__db_main__db_name:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_name is not defined")
			fi

			if [ -z "${var_load__db_main__db_user:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_user is not defined")
			fi
			;;
		'postgres')
			if [ -z "${var_load__db_main__db_name:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_name is not defined")
			fi

			if [ -z "${var_load__db_main__db_user:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_user is not defined")
			fi
			;;
		'mongo')
			if [ -z "${var_load__db_main__db_name:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_name is not defined")
			fi

			if [ -z "${var_load__db_main__db_user:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_user is not defined")
			fi

			if [ -z "${var_load__db_main__authentication_database:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__authentication_database is not defined")
			fi
			;;
		'elasticsearch')
			if [ -z "${var_load__db_main__db_host:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_host is not defined")
			fi
			;;
		'prometheus')
			if [ -z "${var_load__db_main__db_host:-}" ]; then
				tmp_errors+=("[shared] [$tmp_info] var_load__db_main__db_host is not defined")
			fi
			;;
		*)
			tmp_errors+=("[shared] var_load_main__db_service value is unsupported (${var_load_main__db_service:-})")
			;;
	esac
fi

# Pod Type

tmp_is_web=''

if [ "${var_load_main__pod_type:-}" = 'app' ] || [ "${var_load_main__pod_type:-}" = 'web' ]; then
	tmp_is_web='true'
fi

tmp_is_db=''

if [ "${var_load_main__pod_type:-}" = 'app' ] || [ "${var_load_main__pod_type:-}" = 'db' ]; then
	tmp_is_db='true'
fi

tmp_db_backup_task_default="db:main:${var_load_main__db_service:-}:backup"
tmp_db_backup_task="${var_load_main__db_backup_task:-$tmp_db_backup_task_default}"

tmp_db_restore_task_default="db:main:${var_load_main__db_service:-}:restore"
tmp_db_restore_task="${var_load_main__db_restore_task:-$tmp_db_restore_task_default}"

if [ -n "${var_load_main__db_service:-}" ]; then
	export var_load_main__db_backup_task="$tmp_db_backup_task"
	export var_load_main__db_restore_task="$tmp_db_restore_task"
fi

# General

export var_run__general__ctx_full_name="${var_load_general__ctx_full_name:-$var_load_name}"
export var_run__general__ctx_prefix_main="${var_load_general__ctx_prefix_main:-}"
export var_run__general__ctx_prefix_run="${var_load_general__ctx_prefix_run:-}"
export var_run__general__shared_network="${var_load_general__shared_network:-}"
export var_run__general__script_dir="${var_load_general__script_dir:-}"
export var_run__general__script_env_file="${var_load_general__script_env_file:-}"
export var_run__general__toolbox_service="${var_load_general__toolbox_service:-toolbox}"
export var_run__general__orchestration="${var_load_general__orchestration:-compose}"
export var_run__general__main_base_dir="${var_load_general__main_base_dir:-}"
export var_run__general__main_base_dir_container="${var_load_general__main_base_dir_container:-}"
export var_run__general__backup_is_delete_old="${var_load_general__backup_is_delete_old:-}"
export var_run__general__s3_cli="${var_load_general__s3_cli:-}"
export var_run__general__define_s3_backup_lifecycle="${var_load_general__define_s3_backup_lifecycle:-}"
export var_run__general__define_s3_uploads_lifecycle="${var_load_general__define_s3_uploads_lifecycle:-}"

export var_run__meta__no_stacktrace="${var_load_meta__no_stacktrace:-}"
export var_run__meta__no_info="${var_load_meta__no_info:-}"
export var_run__meta__no_warn="${var_load_meta__no_warn:-}"
export var_run__meta__no_error="${var_load_meta__no_error:-}"
export var_run__meta__no_info_wrap="${var_load_meta__no_info_wrap:-}"
export var_run__meta__no_summary="${var_load_meta__no_summary:-}"
export var_run__meta__no_colors="${var_load_meta__no_colors:-}"
export var_run__meta__error_on_warn="${var_load_meta__error_on_warn:-}"

if [ "${var_load_general__define_s3_backup_lifecycle:-}" = 'true' ]; then
	tmp_cli="${var_load__s3_backup__cli:-awscli}"

	if [ "$tmp_cli" != 'awscli' ] && [ "$tmp_cli" != 'mc' ] && [ "$tmp_cli" != 'custom' ]; then
		tmp_errors+=("[shared] s3 backup cli ($tmp_cli) unsupported for lifecycle")
	fi
fi

if [ "${var_load_general__define_s3_uploads_lifecycle:-}" = 'true' ]; then
	tmp_cli="${var_load__s3_uploads__cli:-awscli}"

	if [ "$tmp_cli" != 'awscli' ] && [ "$tmp_cli" != 'mc' ] && [ "$tmp_cli" != 'custom' ]; then
		tmp_errors+=("[shared] s3 uploads cli ($tmp_cli) unsupported for lifecycle")
	fi
fi

export var_shared__delete_old__days="${var_load_shared__delete_old__days:-}"
export var_shared__fluentd_output_plugin="${var_load_shared__fluentd_output_plugin:-}"

if [ "${var_load_shared__define_cron:-}" = 'true' ]; then
    export var_shared__define_cron="${var_load_shared__define_cron:-}"
    export var_shared__cron__src="${var_load_shared__cron__src:-}"
    export var_shared__cron__dest="${var_load_shared__cron__dest:-}"
fi

export var_main__pod_type="${var_load_main__pod_type:-}"
export var_load_main__instance_index="${var_load_main__instance_index:-}"
export var_main__local="${var_load_main__local:-}"

export var_main__use_main_network="${var_load_use__main_network:-}"
export var_main__use_internal_ssl="${var_load_use__internal_ssl:-}"
export var_main__use_secrets="${var_load_use__secrets:-}"
export var_main__use_logrotator="${var_load_use__logrotator:-}"
export var_main__use_fluentd="${var_load_use__fluentd:-}"
export var_main__use_internal_fluentd="${var_load_use__internal_fluentd:-}"
export var_main__use_s3="${var_load_use__s3:-}"
export var_main__use_s3_cli_main="${var_load_use__s3_cli_main:-}"
export var_main__use_local_s3="${var_load_use__local_s3:-}"
export var_main__use_wale="${var_load_use__wale:-}"
export var_main__use_wale_restore="${var_load_use__wale_restore:-}"

if [ "$tmp_is_web" = 'true' ]; then
	export var_main__use_nginx="${var_load_use__nginx:-}"
	export var_main__use_haproxy="${var_load_use__haproxy:-}"
	export var_main__use_theia="${var_load_use__theia:-}"
	export var_main__use_minio_gateway="${var_load_use__minio_gateway:-}"
	export var_main__use_varnish="${var_load_use__varnish:-}"
	export var_main__use_pgadmin="${var_load_use__pgadmin:-}"
	export var_main__use_outer_proxy="${var_load_use__outer_proxy:-}"

	if [ "${var_load_use__ssl:-}" = 'true' ]; then
		export var_main__use_certbot="${var_load_use__certbot:-}"
	fi

	if [ "${var_load_use__outer_proxy:-}" = 'true' ]; then
		export var_main__outer_proxy_type="${var_load_shared__outer_proxy_type:-}"
	fi
fi

if [ "$tmp_is_db" = 'true' ]; then
	export var_main__use_mysql="${var_load_use__mysql:-}"
	export var_main__use_postgres="${var_load_use__postgres:-}"
	export var_main__use_mongo="${var_load_use__mongo:-}"
fi

if [ -n "${var_load_main__db_service:-}" ]; then
	export var_run__migrate__db_service="$var_load_main__db_service"
    export var_run__migrate__db_host="${var_load__db_main__db_host:-}"
    export var_run__migrate__db_port="${var_load__db_main__db_port:-}"
	export var_run__migrate__db_name="${var_load__db_main__db_name:-}"
	export var_run__migrate__db_user="${var_load__db_main__db_user:-}"
	export var_run__migrate__db_pass="${var_load__db_main__db_pass:-}"
	export var_run__migrate__db_tls="${var_load__db_main__db_tls:-}"
	export var_run__migrate__db_tls_ca_cert="${var_load__db_main__db_tls_ca_cert:-}"
	export var_run__migrate__db_root_user="${var_load__db_main__db_root_user:-}"
	export var_run__migrate__db_root_pass="${var_load__db_main__db_root_pass:-}"
	export var_run__migrate__db_connect_wait_secs="${var_load__db_main__db_connect_wait_secs:-300}"
fi

# Group Tasks

tmp_group_backup=""

if [ "${var_load_enable__db_backup:-}" = 'true' ] && [ "${var_load_enable__db_backup_sync:-}" = 'true' ]; then
	tmp_errors+=("[shared] db_backup and db_backup_sync are both enabled")
fi

tmp_enable_db_backup="${var_load_enable__db_backup:-}"
[ "$tmp_enable_db_backup" != 'true' ] && tmp_enable_db_backup="${var_load_enable__db_backup_sync:-}"

if [ "$tmp_enable_db_backup" = 'true' ]; then
	if [ "${var_load_enable__custom_db_backup:-}" = 'true' ]; then
		tmp_errors+=("[shared] db_backup and custom_db_backup are both enabled")
	fi
else
	tmp_enable_db_backup="${var_load_enable__custom_db_backup:-}"
fi

export var_run__enable__db_backup="$tmp_enable_db_backup"

if [ "${var_run__enable__db_backup:-}" = 'true' ]; then
	export var_run__enable__main_backup='true'
fi

if [ "${var_load_enable__sync_backup:-}" = 'true' ]; then
	tmp_group_backup="$tmp_group_backup,sync_backup"
	export var_run__enable__main_backup='true'
fi

tmp_enable_uploads_backup="${var_load_enable__uploads_backup:-}"

if [ "$tmp_enable_uploads_backup" = 'true' ]; then
	if [ "${var_load_enable__custom_uploads_backup:-}" = 'true' ]; then
		tmp_errors+=("[shared] uploads_backup and custom_uploads_backup are both enabled")
	fi
else
	tmp_enable_uploads_backup="${var_load_enable__custom_uploads_backup:-}"
fi

export var_run__enable__uploads_backup="$tmp_enable_uploads_backup"

if [ "$tmp_is_db" = 'true' ]; then
	if [ "${var_load_enable__db_backup_sync:-}" = 'true' ]; then
		tmp_group_backup="$tmp_group_backup,db_backup_sync"
	elif [ "$tmp_enable_db_backup" = 'true' ]; then
		tmp_group_backup="$tmp_group_backup,db_backup"
	fi
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "$tmp_enable_uploads_backup" = 'true' ]; then
		tmp_group_backup="$tmp_group_backup,uploads_backup"
	fi
fi

if [ "${var_load_enable__logs_backup:-}" = 'true' ]; then
	tmp_group_backup="$tmp_group_backup,logs_backup"
	export var_run__enable__main_backup='true'
fi

if [ -n "$tmp_group_backup" ]; then
	tmp_group_backup="${tmp_group_backup:1}"
fi

export var_run__tasks__backup='group_backup'
export var_task__group_backup__task__type='group'
export var_task__group_backup__group_task__task_names="$tmp_group_backup"

tmp_group_setup=""

if [ "${var_load_enable__db_setup:-}" = 'true' ] && [ "${var_load_enable__db_setup_sync:-}" = 'true' ]; then
	tmp_errors+=("[shared] db_setup and db_setup_sync are both enabled")
fi

tmp_enable_db_setup="${var_load_enable__db_setup:-}"
[ "$tmp_enable_db_setup" != 'true' ] && tmp_enable_db_setup="${var_load_enable__db_setup_sync:-}"

if [ "$tmp_enable_db_setup" = 'true' ]; then
	if [ "${var_load_enable__custom_db_setup:-}" = 'true' ]; then
		tmp_errors+=("[shared] db_setup and custom_db_setup are both enabled")
	fi
else
	tmp_enable_db_setup="${var_load_enable__custom_db_setup:-}"
fi

export var_run__enable__db_setup="$tmp_enable_db_setup"

if [ "${var_run__enable__db_setup:-}" = 'true' ]; then
	export var_run__enable__main_setup='true'
fi

if [ "$tmp_enable_db_setup" = 'true' ] &&  [ "${var_load_enable__db_setup_new:-}" = 'true' ]; then
	tmp_errors+=("[shared] db_setup and db_setup_new are both enabled")
fi

tmp_enable_uploads_setup="${var_load_enable__uploads_setup:-}"

if [ "$tmp_enable_uploads_setup" = 'true' ]; then
	if [ "${var_load_enable__custom_uploads_setup:-}" = 'true' ]; then
		tmp_errors+=("[shared] uploads_setup and custom_uploads_setup are both enabled")
	fi
else
	tmp_enable_uploads_setup="${var_load_enable__custom_uploads_setup:-}"
fi

export var_run__enable__uploads_setup="$tmp_enable_uploads_setup"

if [ "$tmp_enable_uploads_setup" = 'true' ] &&  [ "${var_load_use__s3_storage:-}" = 'true' ]; then
	tmp_errors+=("[shared] uploads_setup is enabled with use_s3_storage=true")
fi

if [ "${var_load_enable__sync_setup:-}" = 'true' ]; then
	tmp_group_setup="$tmp_group_setup,sync_setup"
	export var_run__enable__main_setup='true'
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "$tmp_enable_uploads_setup" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,uploads_setup"
	fi

	if [ "${var_load_enable__db_setup_new:-}" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,db_setup_new"
	fi
fi

if [ "$tmp_is_db" = 'true' ]; then
	if [ "${var_load_enable__db_setup_sync:-}" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,db_setup_sync"
	elif [ "$tmp_enable_db_setup" = 'true' ]; then
		tmp_group_setup="$tmp_group_setup,db_setup"
	fi
fi

if [ "${var_load_enable__logs_setup:-}" = 'true' ]; then
	tmp_group_setup="$tmp_group_setup,logs_setup"
	export var_run__enable__main_setup='true'
fi

if [ -n "$tmp_group_setup" ]; then
	tmp_group_setup="${tmp_group_setup:1}"
fi

export var_run__tasks__setup='group_setup'
export var_task__group_setup__task__type='group'
export var_task__group_setup__group_task__task_names="$tmp_group_setup"

export var_run__enable__backup_replica="${var_load_enable__backup_replica:-}"
export var_run__enable__uploads_replica="${var_load_enable__uploads_replica:-}"

# Tasks

if [ "$tmp_is_web" = 'true' ]; then
	export var_shared__block_ips__action_exec__enabled="${var_load__block_ips:-}"

	if [ "${var_load__block_ips:-}" = 'true' ]; then
		if [ "${var_load_use__haproxy:-}" = 'true' ]; then
			export var_shared__block_ips__action_exec__service='haproxy'
		elif [ "${var_load_use__nginx:-}" = 'true' ]; then
			export var_shared__block_ips__action_exec__service='nginx'
		else
			export var_shared__block_ips__action_exec__service=''
		fi

		export var_shared__block_ips__action_exec__max_amount="${var_load__block_ips__max_amount:-10000}"
		export var_shared__block_ips__action_exec__amount_day="${var_load__block_ips__amount_day:-20000}"
		export var_shared__block_ips__action_exec__amount_hour="${var_load__block_ips__amount_hour:-3600}"
	fi
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "${var_load_use__certbot:-}" = 'true' ]; then
		if [ -z "${var_load__certbot__main_domain:-}" ]; then
			tmp_errors+=("[shared] var_load__certbot__main_domain is not defined")
		fi

		if [ -z "${var_load__certbot__domains:-}" ]; then
			tmp_errors+=("[shared] var_load__certbot__domains is not defined")
		fi

		if [ "${var_load_main__local:-}" != 'true' ]; then
			if [ -z "${var_load__certbot__email:-}" ]; then
				tmp_errors+=("[shared] var_load__certbot__email is not defined")
			fi
		fi

		export var_task__certbot__task__type='certbot'
		export var_task__certbot__certbot_task__certbot_cmd='setup'
		export var_task__certbot__certbot_subtask__certbot_service='certbot'
		export var_task__certbot__certbot_subtask__toolbox_service='toolbox'
		export var_task__certbot__certbot_subtask__data_base_path='/var/main/data/sync/certbot'

		if [ "${var_load_use__haproxy:-}" = 'true' ]; then
			export var_task__certbot__certbot_subtask__webservice_type='haproxy'
		elif [ "${var_load_use__nginx:-}" = 'true' ]; then
			export var_task__certbot__certbot_subtask__webservice_type='nginx'
		else
			export var_task__certbot__certbot_subtask__webservice_type=''
		fi

		export var_task__certbot__certbot_subtask__dev="${var_load__certbot__dev:-$var_main__local}"
		export var_task__certbot__certbot_subtask__domains="${var_load__certbot__domains:-}"
		export var_task__certbot__certbot_subtask__email="${var_load__certbot__email:-}"
		export var_task__certbot__certbot_subtask__force="${var_load__certbot__force:-}"
		export var_task__certbot__certbot_subtask__main_domain="${var_load__certbot__main_domain:-}"
		export var_task__certbot__certbot_subtask__rsa_key_size="${var_load__certbot__rsa_key_size:-4096}"
		export var_task__certbot__certbot_subtask__staging="${var_load__certbot__staging:-$var_main__local}"
	fi
fi

if [ "$tmp_is_db" = 'true' ] && [ "$tmp_enable_db_backup" = 'true' ]; then
	if [ "${var_load_enable__db_backup:-}" = 'true' ]; then
		if [ -z "${var_load_main__db_service:-}" ]; then
			tmp_errors+=("[shared] var_load_main__db_service is not defined (db_backup)")
		fi

		tmp_db_src_base_dir="/tmp/main/tmp/${var_load_main__db_service:-}/backup"
		tmp_db_tmp_dir="/tmp/main/tmp/backup/${var_load_main__db_service:-}"

		export var_task__db_backup__task__type='backup'
		export var_task__db_backup__backup_task__subtask_cmd_local='shared:db:task:backup_local'
		export var_task__db_backup__backup_task__subtask_cmd_remote='backup:remote:default'
		export var_task__db_backup__backup_task__is_compressed_file="${var_load__db_backup__is_compressed_file:-}"

		tmp_default_compress_flat=''

		if [ "${var_load_main__db_backup_include_src:-}" = 'true' ]; then
			tmp_src="${var_load_main__db_backup_src:-$tmp_db_src_base_dir}"
			tmp_default_compress_flat='true'
			export var_task__db_backup__backup_task__backup_src="$tmp_src"
		fi

		if [ "${var_task__db_backup__backup_task__is_compressed_file:-}" = 'true' ]; then
			tmp_default_compressed_file_name="${var_load__db_main__db_name:-}.[[ datetime ]].[[ random ]].zip"
			tmp_compressed_file_name="${var_load__db_backup__compressed_file_name:-$tmp_default_compressed_file_name}"

			export var_task__db_backup__backup_task__compress_type="${var_load__db_backup__compress_type:-zip}"
			export var_task__db_backup__backup_task__compress_dest_file="$tmp_db_tmp_dir/$tmp_compressed_file_name"
			export var_task__db_backup__backup_task__compress_flat="${var_load__db_backup__compress_flat:-$tmp_default_compress_flat}"
			export var_task__db_backup__backup_task__compress_pass="${var_load__db_backup__compress_pass:-}"
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
		export var_task__db_backup__backup_local__db_subtask_cmd="$tmp_db_backup_task"
		export var_task__db_backup__backup_local__db_task_base_dir="$tmp_db_src_base_dir"

		if [ "${var_load_main__db_backup_is_file:-}" = 'true' ]; then
			tmp_default_extension='sql'
			tmp_default_extension="${var_load_main__db_backup_extension:-$tmp_default_extension}"
			tmp_default_file_name="${var_load__db_main__db_name:-}.${tmp_default_extension}"

			export var_task__db_backup__backup_local__db_file_name="${tmp_default_file_name:-}"
		fi

		tmp_default_sync_dir='db/[[ date ]]'

		if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
			tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (db_backup)")
		fi

		export var_task__db_backup__backup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
		export var_task__db_backup__backup_remote__backup_bucket_sync_dir="${var_load__db_backup__backup_bucket_sync_dir:-$tmp_default_sync_dir}"
		export var_task__db_backup__backup_remote__backup_date_format="${var_load__db_backup__backup_date_format:-}"
		export var_task__db_backup__backup_remote__backup_time_format="${var_load__db_backup__backup_time_format:-}"
		export var_task__db_backup__backup_remote__backup_datetime_format="${var_load__db_backup__backup_datetime_format:-}"
	elif [ "${var_load_enable__db_backup_sync:-}" = 'true' ]; then
		if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
			tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (db_backup_sync)")
		fi

		if [ -z "${var_load__db_backup_sync__src_relpath:-}" ]; then
			tmp_errors+=("[shared] var_load__db_backup_sync__src_relpath is not defined")
		fi

		tmp_default_sync_dir="db/${var_load_main__instance_index:-}"

		export var_task__db_backup_sync__task__type='backup'
		export var_task__db_backup_sync__backup_task__subtask_cmd_remote='backup:remote:default'
		export var_task__db_backup_sync__backup_task__backup_src="/var/main/data/${var_load__db_backup_sync__src_relpath:-}"
		export var_task__db_backup_sync__backup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
		export var_task__db_backup_sync__backup_remote__backup_bucket_sync_dir="${var_load__db_backup_sync__backup_bucket_sync_dir:-$tmp_default_sync_dir}"
		export var_task__db_backup_sync__backup_remote__backup_date_format="${var_load__db_backup_sync__backup_date_format:-}"
		export var_task__db_backup_sync__backup_remote__backup_time_format="${var_load__db_backup_sync__backup_time_format:-}"
		export var_task__db_backup_sync__backup_remote__backup_datetime_format="${var_load__db_backup_sync__backup_datetime_format:-}"
	fi
fi

if [ -n "${var_load_main__db_service:-}" ]; then
	export var_task__db_main__db_subtask__db_service="${var_load_main__db_service:-}"
    export var_task__db_main__db_subtask__db_host="${var_load__db_main__db_host:-}"
    export var_task__db_main__db_subtask__db_port="${var_load__db_main__db_port:-}"
	export var_task__db_main__db_subtask__db_name="${var_load__db_main__db_name:-}"
	export var_task__db_main__db_subtask__db_user="${var_load__db_main__db_user:-}"
	export var_task__db_main__db_subtask__db_pass="${var_load__db_main__db_pass:-}"
	export var_task__db_main__db_subtask__db_tls="${var_load__db_main__db_tls:-}"
	export var_task__db_main__db_subtask__db_tls_ca_cert="${var_load__db_main__db_tls_ca_cert:-}"
	export var_task__db_main__db_subtask__db_connect_wait_secs="${var_load__db_main__db_connect_wait_secs:-300}"
	export var_task__db_main__db_subtask__authentication_database="${var_load__db_main__authentication_database:-}"
fi

if [ "$tmp_is_db" = 'true' ] && [ "$tmp_enable_db_setup" = 'true' ]; then
	tmp_default_file_to_skip='/tmp/main/setup/db.skip'

	if [ "${var_load_enable__db_setup:-}" = 'true' ]; then
		if [ "${var_load_enable__db_setup_new:-}" = 'true' ]; then
			tmp_errors+=("[shared] var_load_enable__db_setup and var_load_enable__db_setup_new are both true (choose only one)")
		fi

		if [ -z "${var_load_main__db_service:-}" ]; then
			tmp_errors+=("[shared] var_load_main__db_service is not defined (db_setup)")
		fi

		tmp_db_dest_dir="/tmp/main/tmp/${var_load_main__db_service:-}/restore"
		tmp_db_tmp_dir="/tmp/main/tmp/restore/${var_load_main__db_service:-}"

		tmp_file_to_skip="${var_load__db_setup__verify_file_to_skip:-$tmp_default_file_to_skip}"

		tmp_default_compressed_file_name="${var_load__db_main__db_name:-}.zip"
		tmp_compressed_file_name="${var_load__db_setup__compressed_file_name:-$tmp_default_compressed_file_name}"
		tmp_compressed_file_path="$tmp_db_tmp_dir/$tmp_compressed_file_name"

		tmp_default_extension='sql'
		tmp_default_extension="${var_load_main__db_backup_extension:-$tmp_default_extension}"
		tmp_default_file_name="${var_load__db_main__db_name:-}.${tmp_default_extension}"
		tmp_db_file_name="${var_load__db_setup__db_file_name:-$tmp_default_file_name}"
		tmp_file_path="$tmp_db_dest_dir/$tmp_db_file_name"
		tmp_db_backup_is_file="${var_load_main__db_backup_is_file:-}"
		tmp_is_file="${var_load_db_restore_is_file:-$tmp_db_backup_is_file}"

		export var_task__db_setup__task__type='setup'
		export var_task__db_setup__setup_task__verify_file_to_skip="$tmp_file_to_skip"
		export var_task__db_setup__setup_task__subtask_cmd_verify='shared:db:task:setup_verify'
		export var_task__db_setup__setup_task__subtask_cmd_remote='setup:remote:default'
		export var_task__db_setup__setup_task__subtask_cmd_local='shared:db:task:setup_local'
		export var_task__db_setup__setup_task__is_compressed_file="${var_load__db_setup__is_compressed_file:-}"

		if [ "${var_task__db_setup__setup_task__is_compressed_file:-}" = 'true' ]; then
			export var_task__db_setup__setup_task__compress_type="${var_load__db_setup__compress_type:-zip}"
			export var_task__db_setup__setup_task__compress_src_file="$tmp_compressed_file_path"
			export var_task__db_setup__setup_task__compress_dest_dir="${tmp_db_dest_dir:-}"
			export var_task__db_setup__setup_task__compress_pass="${var_load__db_setup__compress_pass:-}"
		fi

		export var_task__db_setup__setup_task__recursive_dir="${tmp_db_dest_dir:-}"
		export var_task__db_setup__setup_task__recursive_mode="${var_load__db_setup__recursive_mode:-}"
		export var_task__db_setup__setup_task__recursive_mode_dir="${var_load__db_setup__recursive_mode_dir:-}"
		export var_task__db_setup__setup_task__recursive_mode_file="${var_load__db_setup__recursive_mode_file:-}"
		export var_task__db_setup__setup_task__file_to_clear="${var_load__db_setup__file_to_clear:-}"
		export var_task__db_setup__setup_task__dir_to_clear="${var_load__db_setup__dir_to_clear:-}"

		export var_task__db_setup__setup_verify__task_name='db_main'
		export var_task__db_setup__setup_verify__db_subtask_cmd="db:main:${var_load_main__db_service:-}:restore:verify"

		export var_task__db_setup__setup_remote__restore_use_s3="${var_load__db_setup__restore_use_s3:-}"

		if [ "${var_load__db_setup__restore_use_s3:-}" != 'true' ]; then
			if [ -z "${var_load__db_setup__restore_remote_file:-}" ]; then
				tmp_errors+=("[shared] var_load__db_setup__restore_remote_file is not defined (restore with use_s3=false)")
			fi

			export var_task__db_setup__setup_remote__restore_remote_file="${var_load__db_setup__restore_remote_file:-}"

			if [ "${var_task__db_setup__setup_task__is_compressed_file:-}" = 'true' ]; then
				export var_task__db_setup__setup_remote__restore_dest_file="$tmp_compressed_file_path"
			else
				if [ "${tmp_is_file:-}" != 'true' ]; then
					tmp_msg="restore_is_file not true (or undefined and backup_is_file not true)"
					tmp_errors+=("[shared] [db_setup] non-s3 and non-compressed file with ")
				fi

				export var_task__db_setup__setup_remote__restore_dest_file="${tmp_file_path:-}"
			fi
		else
			if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
				tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (db_setup, restore_use_s3=true)")
			fi

			export var_task__db_setup__setup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
			export var_task__db_setup__setup_remote__restore_s3_sync="${var_load__db_setup__restore_s3_sync:-}"

			if [ "${var_load__db_setup__restore_s3_sync:-}" = 'true' ]; then
				export var_task__db_setup__setup_remote__restore_bucket_path_dir="${var_load__db_setup__restore_bucket_path_dir:-}"

				if [ "${var_task__db_setup__setup_task__is_compressed_file:-}" = 'true' ]; then
					export var_task__db_setup__setup_remote__restore_dest_file="${tmp_compressed_file_path:-}"
				else
					export var_task__db_setup__setup_remote__restore_dest_dir="${tmp_db_dest_dir:-}"
				fi
			else
				if [ -z "${var_load__db_setup__restore_bucket_path_file:-}" ]; then
					tmp_errors+=("[shared] var_load__db_setup__restore_bucket_path_file is not defined")
				fi

				export var_task__db_setup__setup_remote__restore_bucket_path_file="${var_load__db_setup__restore_bucket_path_file:-}"

				if [ "${var_task__db_setup__setup_task__is_compressed_file:-}" = 'true' ]; then
					export var_task__db_setup__setup_remote__restore_dest_file="${tmp_compressed_file_path:-}"
				else
					if [ "${tmp_is_file:-}" != 'true' ]; then
						tmp_msg="restore_is_file not true (or undefined and backup_is_file not true)"
						tmp_errors+=("[shared] [db_setup] s3 non-sync and non-compressed file with $tmp_msg")
					fi

					export var_task__db_setup__setup_remote__restore_dest_file="${tmp_file_path:-}"
				fi
			fi
		fi

		export var_task__db_setup__setup_local__task_name='db_main'
		export var_task__db_setup__setup_local__db_subtask_cmd="$tmp_db_restore_task"
		export var_task__db_setup__setup_local__db_task_base_dir="$tmp_db_dest_dir"

		if [ "${var_load_main__db_restore_is_file:-}" = 'true' ]; then
			export var_task__db_setup__setup_local__db_file_name="$tmp_db_file_name"
		fi
	elif [ "${var_load_enable__db_setup_sync:-}" = 'true' ]; then
		if [ -z "${var_load__db_setup_sync__dest_dir_relpath:-}" ]; then
			tmp_errors+=("[shared] var_load__db_setup_sync__dest_dir_relpath is not defined")
		fi

		tmp_dest_dir="/var/main/data/${var_load__db_setup_sync__dest_dir_relpath:-}"
		tmp_file_to_skip="${var_load__db_setup_sync__verify_file_to_skip:-$tmp_default_file_to_skip}"

		export var_task__db_setup_sync__task__type='setup'
		export var_task__db_setup_sync__setup_task__subtask_cmd_remote='setup:remote:default'
		export var_task__db_setup_sync__setup_task__verify_file_to_skip="$tmp_file_to_skip"
		export var_task__db_setup_sync__setup_task__recursive_dir="$tmp_dest_dir"
		export var_task__db_setup_sync__setup_task__recursive_mode="${var_load__db_setup_sync__recursive_mode:-}"
		export var_task__db_setup_sync__setup_task__recursive_mode_dir="${var_load__db_setup_sync__recursive_mode_dir:-}"
		export var_task__db_setup_sync__setup_task__recursive_mode_file="${var_load__db_setup_sync__recursive_mode_file:-}"

		export var_task__db_setup_sync__setup_verify__setup_dest_dir_to_verify="$tmp_dest_dir"

		if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
			tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (db_setup_sync)")
		fi

		export var_task__db_setup_sync__setup_remote__restore_use_s3='true'
		export var_task__db_setup_sync__setup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
		export var_task__db_setup_sync__setup_remote__restore_s3_sync='true'
		export var_task__db_setup_sync__setup_remote__restore_dest_dir="$tmp_dest_dir"
		export var_task__db_setup_sync__setup_remote__restore_bucket_path_dir="${var_load__db_setup_sync__restore_bucket_path_dir:-}"
	fi
fi

if [ "${var_load__log_summary__disabled:-}" = 'false' ]; then
    export var_log__summary__days_ago="${var_load__log_summary__days_ago:-1}"
    export var_log__summary__max_amount="${var_load__log_summary__max_amount:-100}"
    export var_log__summary__verify_size_docker_dir="${var_load__log_summary__verify_size_docker_dir:-}"
    export var_log__summary__verify_size_containers="${var_load__log_summary__verify_size_containers:-true}"
fi

if [ "${var_load_enable__logs_backup:-}" = 'true' ]; then
	if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
		tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (logs_backup)")
	fi

    export var_task__logs_backup__task__type='backup'
    export var_task__logs_backup__backup_task__subtask_cmd_remote='backup:remote:default'
    export var_task__logs_backup__backup_task__backup_src='/var/log/main'
    export var_task__logs_backup__backup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
	export var_task__logs_backup__backup_remote__backup_ignore_path='/var/log/main/fluentd/buffer/*'
    export var_task__logs_backup__backup_remote__backup_bucket_sync_dir="log/${var_load_main__pod_type:-}/${var_load_main__instance_index:-}"
fi

if [ "${var_load_enable__logs_setup:-}" = 'true' ]; then
    tmp_dest_dir='/var/log/main'
	tmp_default_file_to_skip='/tmp/main/setup/logs.skip'
	tmp_file_to_skip="${var_load__logs_setup__verify_file_to_skip:-$tmp_default_file_to_skip}"

    export var_task__logs_setup__task__type='setup'
    export var_task__logs_setup__setup_task__subtask_cmd_remote='setup:remote:default'
    export var_task__logs_setup__setup_task__verify_file_to_skip="$tmp_file_to_skip"
    export var_task__logs_setup__setup_task__recursive_dir="$tmp_dest_dir"
    export var_task__logs_setup__setup_task__recursive_mode="${var_load__logs_setup__recursive_mode:-}"
    export var_task__logs_setup__setup_task__recursive_mode_dir="${var_load__logs_setup__recursive_mode_dir:-}"
    export var_task__logs_setup__setup_task__recursive_mode_file="${var_load__logs_setup__recursive_mode_file:-}"

    export var_task__logs_setup__setup_verify__setup_dest_dir_to_verify="$tmp_dest_dir"

	if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
		tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (logs_setup)")
	fi

    export var_task__logs_setup__setup_remote__restore_use_s3='true'
    export var_task__logs_setup__setup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
    export var_task__logs_setup__setup_remote__restore_s3_sync='true'
    export var_task__logs_setup__setup_remote__restore_dest_dir="$tmp_dest_dir"
    export var_task__logs_setup__setup_remote__restore_bucket_path_dir="${var_load__logs_setup__restore_bucket_path_dir:-}"
fi

if [ -n "${var_load__s3_backup__bucket_name:-}" ]; then
	export var_task__s3_backup__s3_subtask__alias='backup'
	export var_task__s3_backup__s3_subtask__service='s3_cli'
	export var_task__s3_backup__s3_subtask__cli_cmd="${var_load__s3_backup__cli_cmd:-exec}"
	export var_task__s3_backup__s3_subtask__tmp_dir='/tmp/main/tmp/s3-backup'
	export var_task__s3_backup__s3_subtask__bucket_name="${var_load__s3_backup__bucket_name:-}"
	export var_task__s3_backup__s3_subtask__bucket_path="${var_load__s3_backup__bucket_path:-}"
	export var_task__s3_backup__s3_subtask__cli="${var_load__s3_backup__cli:-awscli}"
	export var_task__s3_backup__s3_subtask__endpoint="${var_load__s3_backup__endpoint:-}"
	export var_task__s3_backup__s3_subtask__lifecycle_dir="${var_load__s3_backup__lifecycle_dir:-}"
	export var_task__s3_backup__s3_subtask__lifecycle_file="${var_load__s3_backup__lifecycle_file:-}"
	export var_task__s3_backup__s3_subtask__acl="${var_load__s3_backup__acl:-private}"
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "${var_load_enable__backup_replica:-}" = 'true' ]; then
		export var_task__s3_backup_replica__s3_subtask__alias='backup_replica'
		export var_task__s3_backup_replica__s3_subtask__service='s3_cli'
		export var_task__s3_backup_replica__s3_subtask__cli_cmd="${var_load__s3_backup_replica__cli_cmd:-exec}"
		export var_task__s3_backup_replica__s3_subtask__tmp_dir='/tmp/main/tmp/s3-backup-replica'
		export var_task__s3_backup_replica__s3_subtask__bucket_name="${var_load__s3_backup_replica__bucket_name:-}"
		export var_task__s3_backup_replica__s3_subtask__bucket_path="${var_load__s3_backup_replica__bucket_path:-}"
		export var_task__s3_backup_replica__s3_subtask__cli="${var_load__s3_backup_replica__cli:-awscli}"
		export var_task__s3_backup_replica__s3_subtask__endpoint="${var_load__s3_backup_replica__endpoint:-}"
	fi
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ -n "${var_load__s3_uploads__bucket_name:-}" ]; then
		export var_task__s3_uploads__s3_subtask__alias='uploads'
		export var_task__s3_uploads__s3_subtask__service='s3_cli'
		export var_task__s3_uploads__s3_subtask__cli_cmd="${var_load__s3_uploads__cli_cmd:-exec}"
		export var_task__s3_uploads__s3_subtask__tmp_dir='/tmp/main/tmp/s3-uploads'
		export var_task__s3_uploads__s3_subtask__bucket_name="${var_load__s3_uploads__bucket_name:-}"
		export var_task__s3_uploads__s3_subtask__bucket_path="${var_load__s3_uploads__bucket_path:-}"
		export var_task__s3_uploads__s3_subtask__cli="${var_load__s3_uploads__cli:-awscli}"
		export var_task__s3_uploads__s3_subtask__endpoint="${var_load__s3_uploads__endpoint:-}"
		export var_task__s3_uploads__s3_subtask__lifecycle_dir="${var_load__s3_uploads__lifecycle_dir:-}"
		export var_task__s3_uploads__s3_subtask__lifecycle_file="${var_load__s3_uploads__lifecycle_file:-}"
		export var_task__s3_uploads__s3_subtask__acl="${var_load__s3_uploads__acl:-public-read}"
	fi
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "${var_load_enable__uploads_replica:-}" = 'true' ]; then
		export var_task__s3_uploads_replica__s3_subtask__alias='uploads_replica'
		export var_task__s3_uploads_replica__s3_subtask__service='s3_cli'
		export var_task__s3_uploads_replica__s3_subtask__cli_cmd="${var_load__s3_uploads_replica__cli_cmd:-exec}"
		export var_task__s3_uploads_replica__s3_subtask__tmp_dir='/tmp/main/tmp/s3-uploads-replica'
		export var_task__s3_uploads_replica__s3_subtask__bucket_name="${var_load__s3_uploads_replica__bucket_name:-}"
		export var_task__s3_uploads_replica__s3_subtask__bucket_path="${var_load__s3_uploads_replica__bucket_path:-}"
		export var_task__s3_uploads_replica__s3_subtask__cli="${var_load__s3_uploads_replica__cli:-awscli}"
		export var_task__s3_uploads_replica__s3_subtask__endpoint="${var_load__s3_uploads_replica__endpoint:-}"
	fi
fi

if [ "${var_load_enable__sync_backup:-}" = 'true' ]; then
    export var_task__sync_backup__task__type='backup'
    export var_task__sync_backup__backup_task__subtask_cmd_remote='backup:remote:default'
    export var_task__sync_backup__backup_task__backup_src='/var/main/data/sync'
    export var_task__sync_backup__backup_remote__backup_bucket_sync_dir='sync'
    export var_task__sync_backup__backup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
fi

if [ "${var_load_enable__sync_setup:-}" = 'true' ]; then
    tmp_dest_dir='/var/main/data/sync'
	tmp_default_file_to_skip='/tmp/main/setup/sync.skip'
	tmp_file_to_skip="${var_load__sync_setup__verify_file_to_skip:-$tmp_default_file_to_skip}"

    export var_task__sync_setup__task__type='setup'
    export var_task__sync_setup__setup_task__subtask_cmd_remote='setup:remote:default'
    export var_task__sync_setup__setup_task__verify_file_to_skip="$tmp_file_to_skip"
    export var_task__sync_setup__setup_task__recursive_dir="$tmp_dest_dir"
    export var_task__sync_setup__setup_task__recursive_mode="${var_load__sync_setup__recursive_mode:-}"
    export var_task__sync_setup__setup_task__recursive_mode_dir="${var_load__sync_setup__recursive_mode_dir:-}"
    export var_task__sync_setup__setup_task__recursive_mode_file="${var_load__sync_setup__recursive_mode_file:-}"

    export var_task__sync_setup__setup_verify__setup_dest_dir_to_verify="$tmp_dest_dir"

	if [ -z "${var_load__s3_backup__bucket_name:-}" ]; then
		tmp_errors+=("[shared] var_load__s3_backup__bucket_name is not defined (sync_setup)")
	fi

    export var_task__sync_setup__setup_remote__restore_use_s3='true'
    export var_task__sync_setup__setup_remote__restore_s3_sync='true'
    export var_task__sync_setup__setup_remote__subtask_cmd_s3='s3:subtask:s3_backup'
    export var_task__sync_setup__setup_remote__restore_dest_dir="$tmp_dest_dir"
    export var_task__sync_setup__setup_remote__restore_bucket_path_dir="${var_load__sync_setup__restore_bucket_path_dir:-}"
fi

if [ "$tmp_is_web" = 'true' ]; then
	if [ "${var_load_enable__uploads_backup:-}" = 'true' ]; then
		tmp_uploads_src_dir="/var/main/data/${var_load_name:-}/uploads"
		tmp_uploads_tmp_dir='/tmp/main/tmp/backup/uploads'

		tmp_compress_type="${var_load__uploads_backup__compress_type:-zip}"
		tmp_default_compressed_file_name='uploads.[[ datetime ]].[[ random ]].zip'
		tmp_compressed_file_name="${var_load__uploads_backup__compressed_file_name:-$tmp_default_compressed_file_name}"
		tmp_uploads_compress_dest_file="${tmp_uploads_tmp_dir}/${tmp_compressed_file_name}"

		tmp_default_sync_dir='uploads/[[ date ]]'
		tmp_sync_dir="${var_load__uploads_backup__backup_bucket_sync_dir:-$tmp_default_sync_dir}"

		export var_task__uploads_backup__task__type='backup'
		export var_task__uploads_backup__backup_task__backup_src="$tmp_uploads_src_dir"
		export var_task__uploads_backup__backup_task__subtask_cmd_remote='backup:remote:default'
		export var_task__uploads_backup__backup_task__is_compressed_file="${var_load__uploads_backup__is_compressed_file:-}"

		if [ "${var_load__uploads_backup__is_compressed_file:-}" = 'true' ]; then
			export var_task__uploads_backup__backup_task__compress_type="$tmp_compress_type"
			export var_task__uploads_backup__backup_task__compress_dest_file="$tmp_uploads_compress_dest_file"
			export var_task__uploads_backup__backup_task__compress_flat="${var_load__uploads_backup__compress_flat:-}"
			export var_task__uploads_backup__backup_task__compress_pass="${var_load__uploads_backup__compress_pass:-}"
		fi

		export var_task__uploads_backup__backup_task__backup_date_format="${var_load__uploads_backup__backup_date_format:-}"
		export var_task__uploads_backup__backup_task__backup_time_format="${var_load__uploads_backup__backup_time_format:-}"
		export var_task__uploads_backup__backup_task__backup_datetime_format="${var_load__uploads_backup__backup_datetime_format:-}"
		export var_task__uploads_backup__backup_task__recursive_dir="$tmp_uploads_tmp_dir"
		export var_task__uploads_backup__backup_task__recursive_mode="${var_load__uploads_backup__recursive_mode:-}"
		export var_task__uploads_backup__backup_task__recursive_mode_dir="${var_load__uploads_backup__recursive_mode_dir:-}"
		export var_task__uploads_backup__backup_task__recursive_mode_file="${var_load__uploads_backup__recursive_mode_file:-}"
		export var_task__uploads_backup__backup_task__file_to_clear="${var_load__uploads_backup__file_to_clear:-}"
		export var_task__uploads_backup__backup_task__dir_to_clear="${var_load__uploads_backup__dir_to_clear:-}"

		if [ -z "${var_load__s3_uploads__bucket_name:-}" ]; then
			tmp_errors+=("[shared] var_load__s3_uploads__bucket_name is not defined (uploads_backup)")
		fi

		export var_task__uploads_backup__backup_remote__subtask_cmd_s3='s3:subtask:s3_uploads'
		export var_task__uploads_backup__backup_remote__backup_bucket_sync_dir="$tmp_sync_dir"
		export var_task__uploads_backup__backup_remote__backup_date_format="${var_load__uploads_backup__backup_date_format:-}"
		export var_task__uploads_backup__backup_remote__backup_time_format="${var_load__uploads_backup__backup_time_format:-}"
		export var_task__uploads_backup__backup_remote__backup_datetime_format="${var_load__uploads_backup__backup_datetime_format:-}"
	fi

	if [ "${var_load_enable__uploads_setup:-}" = 'true' ]; then
		tmp_restore_use_s3="${var_load__uploads_setup__restore_use_s3:-}"
		tmp_restore_s3_sync="${var_load__uploads_setup__restore_s3_sync:-}"
		tmp_is_compressed_file="${var_load__uploads_setup__is_compressed_file:-}"
		tmp_compressed_inner_dir="${var_load__uploads_setup__restore_compressed_inner_dir:-}"
		tmp_dest_dirname="${var_load__uploads_setup__dest_dirname:-uploads}"

		tmp_uploads_dest_dir_base="/var/main/data/${var_load_name:-}"
		tmp_uploads_dest_dir="$tmp_uploads_dest_dir_base/$tmp_dest_dirname"
		tmp_uploads_tmp_base_dir="/tmp/main/tmp/${var_load_name:-}"

		tmp_default_file_to_skip='/tmp/main/setup/uploads.skip'
		tmp_file_to_skip="${var_load__uploads_setup__verify_file_to_skip:-$tmp_default_file_to_skip}"
		tmp_compress_type="${var_load__uploads_setup__compress_type:-zip}"

		tmp_default_compressed_file_name='uploads.zip'
		tmp_compressed_file_name="${var_load__uploads_setup__compressed_file_name:-$tmp_default_compressed_file_name}"
		tmp_compressed_file_path="/tmp/main/tmp/restore/uploads/$tmp_compressed_file_name"

		export var_task__uploads_setup__task__type='setup'
		export var_task__uploads_setup__setup_task__subtask_cmd_remote='setup:remote:default'
		export var_task__uploads_setup__setup_task__verify_file_to_skip="$tmp_file_to_skip"
		export var_task__uploads_setup__setup_task__recursive_dir="${tmp_uploads_dest_dir:-}"
		export var_task__uploads_setup__setup_task__is_compressed_file="${tmp_is_compressed_file:-}"

		if [ "${tmp_is_compressed_file:-}" = 'true' ]; then
			if [ -z "${tmp_compressed_inner_dir:-}" ]; then
				tmp_compress_dest_dir="$tmp_uploads_dest_dir"
			elif [ "${tmp_compressed_inner_dir:-}" = "${tmp_dest_dirname:-}" ]; then
				tmp_compress_dest_dir="$tmp_uploads_dest_dir_base"
			else
				tmp_compress_dest_dir="$tmp_uploads_tmp_base_dir"
				tmp_uploads_tmp_dir="${tmp_uploads_tmp_base_dir}/${tmp_compressed_inner_dir}"

				export var_task__uploads_setup__setup_task__recursive_dir="${tmp_uploads_tmp_dir:-}"
				export var_task__uploads_setup__setup_task__move_src="${tmp_uploads_tmp_dir:-}"
				export var_task__uploads_setup__setup_task__move_dest="${tmp_uploads_dest_dir:-}"
				export var_task__uploads_setup__setup_task__file_to_clear=""
				export var_task__uploads_setup__setup_task__dir_to_clear="${tmp_uploads_tmp_dir:-}"
			fi

			export var_task__uploads_setup__setup_task__compress_type="$tmp_compress_type"
			export var_task__uploads_setup__setup_task__compress_src_file="$tmp_compressed_file_path"
			export var_task__uploads_setup__setup_task__compress_dest_dir="$tmp_compress_dest_dir"
			export var_task__uploads_setup__setup_task__compress_pass="${var_load__uploads_setup__compress_pass:-}"
		fi

		export var_task__uploads_setup__setup_task__recursive_mode="${var_load__uploads_setup__recursive_mode:-}"
		export var_task__uploads_setup__setup_task__recursive_mode_dir="${var_load__uploads_setup__recursive_mode_dir:-}"
		export var_task__uploads_setup__setup_task__recursive_mode_file="${var_load__uploads_setup__recursive_mode_file:-}"

		export var_task__uploads_setup__setup_verify__setup_dest_dir_to_verify="$tmp_uploads_dest_dir"
		export var_task__uploads_setup__setup_remote__restore_use_s3="$tmp_restore_use_s3"

		if [ "${tmp_restore_use_s3:-}" != 'true' ]; then
			if [ -z "${var_load__uploads_setup__restore_remote_file:-}" ]; then
				tmp_errors+=("[shared] var_load__uploads_setup__restore_remote_file is not defined")
			fi

			export var_task__uploads_setup__setup_remote__restore_remote_file="${var_load__uploads_setup__restore_remote_file:-}"

			if [ "$tmp_is_compressed_file" = 'true' ]; then
				export var_task__uploads_setup__setup_remote__restore_dest_file="$tmp_compressed_file_path"
			else
				tmp_errors+=("[shared] uploads_setup: use_s3=false and is_compressed_file=false (at least 1 should be true)")
			fi
		else
			if [ -z "${var_load__s3_uploads__bucket_name:-}" ]; then
				tmp_errors+=("[shared] var_load__s3_uploads__bucket_name is not defined (uploads_setup)")
			fi

			export var_task__uploads_setup__setup_remote__subtask_cmd_s3='s3:subtask:s3_uploads'
			export var_task__uploads_setup__setup_remote__restore_s3_sync="$tmp_restore_s3_sync"
			export var_task__uploads_setup__setup_remote__restore_bucket_path_dir="${var_load__uploads_setup__restore_bucket_path_dir:-}"
			export var_task__uploads_setup__setup_remote__restore_bucket_path_file="${var_load__uploads_setup__restore_bucket_path_file:-}"

			if [ "$tmp_is_compressed_file" = 'true' ]; then
				export var_task__uploads_setup__setup_remote__restore_dest_dir=''
				export var_task__uploads_setup__setup_remote__restore_dest_file="$tmp_compressed_file_path"
			else
				export var_task__uploads_setup__setup_remote__restore_dest_dir="$tmp_uploads_dest_dir"
				export var_task__uploads_setup__setup_remote__restore_dest_file=''
			fi
		fi
	fi
fi

tmp_error_count=${#tmp_errors[@]}

if [[ $tmp_error_count -gt 0 ]]; then
	for (( i=1; i<tmp_error_count+1; i++ )); do
		echo "$i/${tmp_error_count}: ${tmp_errors[$i-1]}" >&2
	done
fi