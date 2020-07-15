#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_file="$pod_layer_dir/main/scripts/$var_run__general__orchestration.sh"
pod_script_container_file="$pod_layer_dir/main/scripts/container.sh"
pod_script_upgrade_file="$pod_layer_dir/main/scripts/upgrade.sh"
pod_script_db_file="$pod_layer_dir/main/scripts/db.sh"
pod_script_remote_file="$pod_layer_dir/main/scripts/remote.sh"
pod_script_s3_file="$pod_layer_dir/main/scripts/s3.sh"
pod_script_container_image_file="$pod_layer_dir/main/scripts/container-image.sh"
pod_script_certbot_file="$pod_layer_dir/main/scripts/certbot.sh"
pod_script_nginx_file="$pod_layer_dir/main/scripts/nginx.sh"

CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
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

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
	error "This project must not be in the '/' directory"
fi

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (main)."
fi

shift;

inner_cmd=''
key="$(date '+%Y%m%d_%H%M%S_%3N')"
cmd_path="$(echo "$command" | tr : -)"

case "$command" in
	"u")
		command="env"
		inner_cmd="upgrade"
		;;
	"f")
		command="env"
		inner_cmd="fast-upgrade"
		;;
	"t")
		command="env"
		inner_cmd="fast-update"
		;;
	"s")
		command="env"
		inner_cmd="fast-setup"
		;;
	"p")
		command="env"
		inner_cmd="prepare"
		;;
esac

args=("$@")

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then	 # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"			 # extract long option name
		OPTARG="${OPTARG#$OPT}"	 # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"			# if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		task_name ) arg_task_name="${OPTARG:-}";;
		toolbox_service ) arg_toolbox_service="${OPTARG:-}";;
		s3_cmd ) arg_s3_cmd="${OPTARG:-}";;
		s3_src ) arg_s3_src="${OPTARG:-}";;
		s3_src_rel ) arg_s3_src_rel="${OPTARG:-}";;
		s3_remote_src ) arg_s3_remote_src="${OPTARG:-}";;
		s3_dest ) arg_s3_dest="${OPTARG:-}";;
		s3_dest_rel ) arg_s3_dest_rel="${OPTARG:-}";;
		s3_remote_dest ) arg_s3_remote_dest="${OPTARG:-}";;
		s3_file ) arg_s3_file="${OPTARG:-}";;
		backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		db_subtask_cmd ) arg_db_subtask_cmd="${OPTARG:-}";;
		env_local_repo ) arg_env_local_repo="${OPTARG:-}";;
		ctl_layer_dir ) arg_ctl_layer_dir="${OPTARG:-}";;
		setup_dest_base_dir ) arg_setup_dest_base_dir="${OPTARG:-}";;
		backup_src_base_dir ) arg_backup_src_base_dir="${OPTARG:-}";;
		db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}";;
		db_file_name ) arg_db_file_name="${OPTARG:-}";;
		certbot_cmd ) arg_certbot_cmd="${OPTARG:-}";;
		opts ) arg_opts=( "${@:OPTIND}" ); break;;
		??* ) ;;	# bad long option
		\? )	;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

title="$command"
[ -n "${arg_task_name:-}" ] && title="$title - $arg_task_name"
[ -n "${arg_subtask_cmd:-}" ] && title="$title ($arg_subtask_cmd)"

start="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
		;;
	*)
		>&2 echo -e "${CYAN}$(date '+%F %T') - main - $command - start${NC}"
		;;
esac

case "$command" in
	"env")
		"$pod_script_env_file" "$inner_cmd" ${args[@]+"${args[@]}"}
		;;
	"upgrade"|"fast-upgrade"|"update"|"fast-update")
		"$pod_script_upgrade_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"stop-to-upgrade")
		"$pod_script_env_file" stop ${args[@]+"${args[@]}"}
		;;
	"prepare")
		>&2 info "$command - do nothing..."
		;;
	"local:prepare")
		"$arg_ctl_layer_dir/run" dev-cmd bash "/root/w/r/$arg_env_local_repo/run" ${arg_opts[@]+"${arg_opts[@]}"}
		;;
	"migrate")
		>&2 info "$command - do nothing..."
		;;
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")

		if [ -n "${var_orchestration__main_file:-}" ] && [ -z "${ORCHESTRATION_MAIN_FILE:-}" ]; then
			export ORCHESTRATION_MAIN_FILE="$var_orchestration__main_file"
		fi

		if [ -n "${var_orchestration__run_file:-}" ] && [ -z "${ORCHESTRATION_RUN_FILE:-}" ]; then
			export ORCHESTRATION_RUN_FILE="$var_orchestration__run_file"
		fi

		"$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"main:task:"*)
		task_name="${command#main:task:}"
		prefix="var_task__${task_name}__task_"

		type="${prefix}_type"

		"$pod_script_env_file" "${!type}:task:$task_name"
		;;
	"custom:task:"*)
		task_name="${command#custom:task:}"
		prefix="var_task__${task_name}__custom_task_"

		task="${prefix}_task"

		"$pod_script_env_file" "${!task}"
		;;
	"group:task:"*)
		task_name="${command#group:task:}"
		prefix="var_task__${task_name}__group_task_"

		task_names="${prefix}_task_names"

		task_names_values="${!task_names:-}"

		info "[$task_name] group tasks: $task_names_values"

		if [ -n "$task_names_values" ]; then
			IFS=',' read -r -a tmp <<< "$task_names_values"
			arr=("${tmp[@]}")

			for task_name in "${arr[@]}"; do
				"$pod_script_env_file" "main:task:$task_name"
			done
		fi
		;;
	"setup"|"fast-setup")
		opts=()
		opts+=( "--setup_task_name=${var_run__tasks__setup:-}" )
		"$pod_script_upgrade_file" "$command" "${opts[@]}"
		;;
	"setup:main:network")
		network_name="${var_main__env}-${var_main__ctx}-${var_main__pod_name}-network"
		network_result="$("$pod_script_container_file" network ls --format "{{.Name}}" | grep "^${network_name}$" ||:)"

		if [ -z "$network_result" ]; then
			>&2 info "$command - creating the network $network_name..."
			"$pod_script_container_file" network create -d bridge "$network_name"
		fi
		;;
	"setup:task:"*)
		task_name="${command#setup:task:}"
		prefix="var_task__${task_name}__setup_task_"

		subtask_cmd_verify="${prefix}_subtask_cmd_verify"
		subtask_cmd_remote="${prefix}_subtask_cmd_remote"
		subtask_cmd_local="${prefix}_subtask_cmd_local"
		subtask_cmd_new="${prefix}_subtask_cmd_new"
		setup_run_new_task="${prefix}_setup_run_new_task"
		setup_dest_base_dir="${prefix}_setup_dest_base_dir"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )

		opts+=( "--setup_dest_base_dir=${!setup_dest_base_dir:-}" )
		opts+=( "--subtask_cmd_verify=${!subtask_cmd_verify:-}" )
		opts+=( "--subtask_cmd_remote=${!subtask_cmd_remote:-}" )
		opts+=( "--subtask_cmd_local=${!subtask_cmd_local:-}" )
		opts+=( "--subtask_cmd_new=${!subtask_cmd_new:-}" )
		opts+=( "--setup_run_new_task=${!setup_run_new_task:-}" )

		"$pod_script_upgrade_file" "setup:default" "${opts[@]}"
		;;
	"setup:verify:db")
		prefix="var_task__${arg_task_name}__setup_verify_"

		task_name="${prefix}_task_name"
		db_subtask_cmd="${prefix}_db_subtask_cmd"

		opts=()
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--db_subtask_cmd=${!db_subtask_cmd}" )

		"$pod_script_env_file" "db:subtask:${!task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"setup:verify:default")
		prefix="var_task__${arg_task_name}__setup_verify_"

		setup_dest_dir_to_verify="${prefix}_setup_dest_dir_to_verify"

		opts=()
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$arg_toolbox_service" )

		opts+=( "--setup_dest_dir_to_verify=${!setup_dest_dir_to_verify}" )

		"$pod_script_upgrade_file" "setup:verify" "${opts[@]}"
		;;
	"setup:remote:default")
		prefix="var_task__${arg_task_name}__setup_remote_"

		task_kind="${prefix}_task_kind"
		subtask_cmd_s3="${prefix}_subtask_cmd_s3"
		restore_dest_file="${prefix}_restore_dest_file"
		restore_dest_dir="${prefix}_restore_dest_dir"
		restore_tmp_dir="${prefix}_restore_tmp_dir"
		restore_local_file="${prefix}_restore_local_file"
		restore_remote_file="${prefix}_restore_remote_file"
		restore_remote_bucket_path_file="${prefix}_restore_remote_bucket_path_file"
		restore_remote_bucket_path_dir="${prefix}_restore_remote_bucket_path_dir"
		restore_is_zip_file="${prefix}_restore_is_zip_file"
		restore_zip_pass="${prefix}_restore_zip_pass"
		restore_zip_inner_dir="${prefix}_restore_zip_inner_dir"
		restore_zip_inner_file="${prefix}_restore_zip_inner_file"
		restore_recursive_mode="${prefix}restore_recursive_mode"
		restore_recursive_mode_dir="${prefix}restore_recursive_mode_dir"
		restore_recursive_mode_file="${prefix}restore_recursive_mode_file"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--restore_zip_tmp_file_name=$cmd_path-$key.zip" )
		opts+=( "--restore_dest_base_dir=${arg_setup_dest_base_dir}" )

		opts+=( "--restore_tmp_dir=${!restore_tmp_dir}" )

		opts+=( "--task_kind=${!task_kind:-}" )
		opts+=( "--subtask_cmd_s3=${!subtask_cmd_s3:-}" )
		opts+=( "--restore_dest_file=${!restore_dest_file:-}" )
		opts+=( "--restore_dest_dir=${!restore_dest_dir:-}" )
		opts+=( "--restore_local_file=${!restore_local_file:-}" )
		opts+=( "--restore_remote_file=${!restore_remote_file:-}" )
		opts+=( "--restore_remote_bucket_path_file=${!restore_remote_bucket_path_file:-}" )
		opts+=( "--restore_remote_bucket_path_dir=${!restore_remote_bucket_path_dir:-}" )
		opts+=( "--restore_is_zip_file=${!restore_is_zip_file:-}" )
		opts+=( "--restore_zip_pass=${!restore_zip_pass:-}" )
		opts+=( "--restore_zip_inner_dir=${!restore_zip_inner_dir:-}" )
		opts+=( "--restore_zip_inner_file=${!restore_zip_inner_file:-}" )
		opts+=( "--restore_recursive_mode=${!restore_recursive_mode:-}" )
		opts+=( "--restore_recursive_mode_dir=${!restore_recursive_mode_dir:-}" )
		opts+=( "--restore_recursive_mode_file=${!restore_recursive_mode_file:-}" )

		"$pod_script_remote_file" restore "${opts[@]}"
		;;
	"setup:local:db")
		prefix="var_task__${arg_task_name}__setup_local_"

		task_name="${prefix}_task_name"
		db_subtask_cmd="${prefix}_db_subtask_cmd"
		db_file_name="${prefix}_db_file_name"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--db_task_base_dir=$arg_setup_dest_base_dir" )

		opts+=( "--db_subtask_cmd=${!db_subtask_cmd}" )

		opts+=( "--db_file_name=${!db_file_name:-}" )

		"$pod_script_env_file" "db:subtask:${!task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"backup")
		opts=()

		opts+=( "--backup_task_name=$var_run__tasks__backup" )
		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--backup_local_base_dir=$var_run__general__backup_local_base_dir" )
		opts+=( "--backup_local_dir=$var_run__general__backup_local_base_dir/backup-$key" )
		opts+=( "--backup_delete_old_days=$var_run__general__backup_delete_old_days" )

		"$pod_script_upgrade_file" backup "${opts[@]}"
		;;
	"backup:task:"*)
		task_name="${command#backup:task:}"
		prefix="var_task__${task_name}__backup_task_"

		subtask_cmd_verify="${prefix}_subtask_cmd_verify"
		subtask_cmd_local="${prefix}_subtask_cmd_local"
		subtask_cmd_remote="${prefix}_subtask_cmd_remote"
		backup_src_base_dir="${prefix}_backup_src_base_dir"
		backup_local_static_dir="${prefix}_backup_local_static_dir"
		backup_delete_old_days="${prefix}_backup_delete_old_days"

		backup_local_dir="$var_run__general__backup_local_base_dir/backup-$key"
		backup_delete_old_days="$var_run__general__backup_delete_old_days"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--backup_local_base_dir=$var_run__general__backup_local_base_dir" )
		opts+=( "--backup_local_dir=$var_run__general__backup_local_base_dir/backup-$key" )

		opts+=( "--backup_local_dir=${!backup_local_static_dir:-$backup_local_dir}" )
		opts+=( "--backup_delete_old_days=${!backup_delete_old_days:-$backup_delete_old_days}" )

		opts+=( "--subtask_cmd_verify=${!subtask_cmd_verify:-}" )
		opts+=( "--subtask_cmd_local=${!subtask_cmd_local:-}" )
		opts+=( "--subtask_cmd_remote=${!subtask_cmd_remote:-}" )
		opts+=( "--backup_src_base_dir=${!backup_src_base_dir}" )

		"$pod_script_upgrade_file" "backup:default" "${opts[@]}"
		;;
	"backup:remote:default")
		prefix="var_task__${arg_task_name}__backup_remote_"

		task_kind="${prefix}_task_kind"
		subtask_cmd_s3="${prefix}_subtask_cmd_s3"
		backup_src_dir="${prefix}_backup_src_dir"
		backup_src_file="${prefix}_backup_src_file"
		backup_zip_file="${prefix}_backup_zip_file"
		backup_bucket_static_dir="${prefix}_backup_bucket_static_dir"
		backup_bucket_sync="${prefix}_backup_bucket_sync"
		backup_bucket_sync_dir="${prefix}_backup_bucket_sync_dir"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--backup_src_base_dir=$arg_backup_src_base_dir" )
		opts+=( "--backup_local_dir=$arg_backup_local_dir" )

		opts+=( "--task_kind=${!task_kind}" )
		opts+=( "--subtask_cmd_s3=${!subtask_cmd_s3:-}" )
		opts+=( "--backup_src_dir=${!backup_src_dir:-}" )
		opts+=( "--backup_src_file=${!backup_src_file:-}" )
		opts+=( "--backup_zip_file=${!backup_zip_file:-}" )
		opts+=( "--backup_bucket_static_dir=${!backup_bucket_static_dir:-}" )
		opts+=( "--backup_bucket_sync=${!backup_bucket_sync:-}" )
		opts+=( "--backup_bucket_sync_dir=${!backup_bucket_sync_dir:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
		;;
	"backup:local:db")
		prefix="var_task__${arg_task_name}__backup_local_"

		task_name="${prefix}_task_name"
		db_subtask_cmd="${prefix}_db_subtask_cmd"
		db_file_name="${prefix}_db_file_name"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )
		opts+=( "--db_task_base_dir=$arg_backup_src_base_dir" )

		opts+=( "--db_subtask_cmd=${!db_subtask_cmd}" )
		opts+=( "--db_file_name=${!db_file_name:-}" )

		"$pod_script_env_file" "db:subtask:${!task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"db:task:"*)
		task_name="${command#db:task:}"
		prefix="var_task__${task_name}__db_task_"

		db_subtask_cmd="${prefix}_db_subtask_cmd"
		db_file_name="${prefix}_db_file_name"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${!db_subtask_cmd:-}" )
		opts+=( "--db_file_name=${!db_file_name:-}" )
		opts+=( "--db_task_base_dir=${!db_task_base_dir:-}" )

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask:"*)
		task_name="${command#db:subtask:}"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${arg_db_subtask_cmd:-}" )
		opts+=( "--db_file_name=${arg_db_file_name:-}" )
		opts+=( "--db_task_base_dir=${arg_db_task_base_dir:-}" )

		"$pod_script_env_file" "db:subtask" "${opts[@]}"
		;;
	"db:subtask")
		prefix="var_task__${arg_task_name}__db_subtask_"

		db_service="${prefix}_db_service"
		db_cmd="${prefix}_db_cmd"
		db_name="${prefix}_db_name"
		db_host="${prefix}_db_host"
		db_port="${prefix}_db_port"
		db_user="${prefix}_db_user"
		db_pass="${prefix}_db_pass"
		authentication_database="${prefix}_authentication_database"
		db_connect_wait_secs="${prefix}_db_connect_wait_secs"
		db_file_name="${prefix}_db_file_name"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_task_base_dir=${arg_db_task_base_dir:-}" )
		opts+=( "--db_file_name=${arg_db_file_name:-}" )

		opts+=( "--db_service=${!db_service:-}" )
		opts+=( "--db_cmd=${!db_cmd:-}" )
		opts+=( "--db_name=${!db_name:-}" )
		opts+=( "--db_host=${!db_host:-}" )
		opts+=( "--db_port=${!db_port:-}" )
		opts+=( "--db_user=${!db_user:-}" )
		opts+=( "--db_pass=${!db_pass:-}" )
		opts+=( "--authentication_database=${!authentication_database:-}" )
		opts+=( "--db_connect_wait_secs=${!db_connect_wait_secs:-}" )
		opts+=( "--connection_sleep=${!connection_sleep:-}" )

		"$pod_script_db_file" "$arg_db_subtask_cmd" "${opts[@]}"
		;;
	"run:db:main:"*)
		run_cmd="${command#run:}"
		"$pod_script_db_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"s3:task:"*)
		task_name="${command#s3:task:}"
		prefix="var_task__${task_name}__s3_task_"

		db_subtask_cmd="${prefix}_db_subtask_cmd"
		db_file_name="${prefix}_db_file_name"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--s3_cmd=${!s3_cmd:-}" )
		opts+=( "--s3_src=${!s3_src:-}" )
		opts+=( "--s3_remote_src=${!s3_remote_src:-}" )
		opts+=( "--s3_src_rel=${!s3_src_rel:-}" )
		opts+=( "--s3_dest=${!s3_dest:-}" )
		opts+=( "--s3_remote_dest=${!s3_remote_dest:-}" )
		opts+=( "--s3_dest_rel=${!s3_dest_rel:-}" )
		opts+=( "--s3_file=${!s3_file:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask:"*)
		task_name="${command#s3:subtask:}"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--s3_cmd=${arg_s3_cmd:-}" )
		opts+=( "--s3_src=${arg_s3_src:-}" )
		opts+=( "--s3_remote_src=${arg_s3_remote_src:-}" )
		opts+=( "--s3_src_rel=${arg_s3_src_rel:-}" )
		opts+=( "--s3_dest=${arg_s3_dest:-}" )
		opts+=( "--s3_remote_dest=${arg_s3_remote_dest:-}" )
		opts+=( "--s3_dest_rel=${arg_s3_dest_rel:-}" )
		opts+=( "--s3_file=${arg_s3_file:-}" )

		"$pod_script_env_file" "s3:subtask" "${opts[@]}"
		;;
	"s3:subtask")
		prefix="var_task__${arg_task_name}__s3_subtask_"

		cli="${prefix}_cli"
		cli_cmd="${prefix}_cli_cmd"
		service="${prefix}_service"
		endpoint="${prefix}_endpoint"
		bucket_name="${prefix}_bucket_name"
		bucket_path="${prefix}_bucket_path"
		bucket_src_name="${prefix}_bucket_src_name"
		bucket_src_path="${prefix}_bucket_src_path"
		bucket_dest_name="${prefix}_bucket_dest_name"
		bucket_dest_path="${prefix}_bucket_dest_path"

		bucket_src_name_value="${!bucket_name:-}"
		bucket_src_path_value="${!bucket_path:-}"

		if [ -n "${!bucket_src_name:-}" ]; then
			bucket_src_name_value="${!bucket_src_name:-}"
			bucket_src_path_value="${!bucket_src_path:-}"
		fi

		bucket_src_prefix="$bucket_src_name_value"

		if [ -n "$bucket_src_path_value" ]; then
			bucket_src_prefix="$bucket_src_name_value/$bucket_src_path_value"
		fi

		s3_src="${arg_s3_src:-}"

		if [ "${arg_s3_remote_src:-}" = "true" ]; then
			s3_src="$bucket_src_prefix"

			if [ -n "${arg_s3_src_rel:-}" ];then
				s3_src="$s3_src/$arg_s3_src_rel"
			fi

			s3_src=$(echo "$s3_src" | tr -s /)
			s3_src="s3://$s3_src"
		fi

		bucket_dest_name_value="${!bucket_name:-}"
		bucket_dest_path_value="${!bucket_path:-}"

		if [ -n "${!bucket_dest_name:-}" ]; then
			bucket_dest_name_value="${!bucket_dest_name:-}"
			bucket_dest_path_value="${!bucket_dest_path:-}"
		fi

		bucket_dest_prefix="$bucket_dest_name_value"

		if [ -n "$bucket_dest_path_value" ]; then
			bucket_dest_prefix="$bucket_dest_name_value/$bucket_dest_path_value"
		fi

		s3_dest="${arg_s3_dest:-}"

		if [ "${arg_s3_remote_dest:-}" = "true" ]; then
			s3_dest="$bucket_dest_prefix"

			if [ -n "${arg_s3_dest_rel:-}" ];then
				s3_dest="$s3_dest/$arg_s3_dest_rel"
			fi

			s3_dest=$(echo "$s3_dest" | tr -s /)
			s3_dest="s3://$s3_dest"
		fi

		s3_opts=()

		if [ -n "${arg_s3_file:-}" ]; then
			s3_opts=( --exclude "*" --include "$arg_s3_file" )
		fi

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--s3_service=${!service:-}" )
		opts+=( "--s3_endpoint=${!endpoint:-}" )
		opts+=( "--s3_bucket_name=${!bucket_name:-}" )

		opts+=( "--s3_src=${s3_src:-}" )
		opts+=( "--s3_dest=${s3_dest:-}" )
		opts+=( "--s3_opts" )
		opts+=( ${s3_opts[@]+"${s3_opts[@]}"} )

		inner_cmd="s3:${!cli}:${!cli_cmd}:$arg_s3_cmd"
		info "$command - $inner_cmd"
		"$pod_script_s3_file" "$inner_cmd" "${opts[@]}"
		;;
	"certbot:task:"*)
		task_name="${command#certbot:task:}"
		prefix="var_task__${task_name}__certbot_task_"

		certbot_cmd="${prefix}_certbot_cmd"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=${!certbot_cmd}" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask:"*)
		task_name="${command#certbot:subtask:}"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--certbot_cmd=$arg_certbot_cmd" )

		"$pod_script_env_file" "certbot:subtask" "${opts[@]}"
		;;
	"certbot:subtask")
		prefix="var_task__${arg_task_name}__certbot_subtask_"

		toolbox_service="${prefix}_toolbox_service"
		certbot_service="${prefix}_certbot_service"
		webservice_service="${prefix}_webservice_service"
		webservice_type="${prefix}_webservice_type"
		data_base_path="${prefix}_data_base_path"
		main_domain="${prefix}_main_domain"
		domains="${prefix}_domains"
		rsa_key_size="${prefix}_rsa_key_size"
		email="${prefix}_email"
		dev="${prefix}_dev"
		staging="${prefix}_staging"
		force="${prefix}_force"

		webservice_type_value="${!webservice_type}"

		opts=()

		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=${!toolbox_service}" )
		opts+=( "--certbot_service=${!certbot_service}" )
		opts+=( "--webservice_type=${!webservice_type}" )
		opts+=( "--data_base_path=${!data_base_path}" )
		opts+=( "--main_domain=${!main_domain}" )
		opts+=( "--domains=${!domains}" )
		opts+=( "--rsa_key_size=${!rsa_key_size}" )
		opts+=( "--email=${!email}" )

		opts+=( "--webservice_service=${!webservice_service:-$webservice_type_value}" )
		opts+=( "--dev=${!dev:-}" )
		opts+=( "--dev_renew_days=${!dev_renew_days:-}" )
		opts+=( "--staging=${!staging:-}" )
		opts+=( "--force=${!force:-}" )

		"$pod_script_certbot_file" "certbot:$arg_certbot_cmd" "${opts[@]}"
		;;
	"run:certbot:"*)
		run_cmd="${command#run:}"
		"$pod_script_certbot_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"verify")
		"$pod_script_env_file" "main:task:$var_run__tasks__verify"
		;;
	"verify:db:connection")
		prefix="var_task__${arg_task_name}__verify_db_connection_"

		task_name="${prefix}_task_name"
		db_subtask_cmd="${prefix}_db_subtask_cmd"

		opts=()
		opts+=( "--task_name=$arg_task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--db_subtask_cmd=${!db_subtask_cmd}" )

		"$pod_script_env_file" "db:subtask:${!task_name:-$arg_task_name}" "${opts[@]}"
		;;
	"sync:verify:"*)
		service="${command#sync:verify:}"
		reload="$("$pod_script_env_file" "sync:prepare:$service")" || error "$command"

		if [ "$reload" = "true" ]; then
			"$pod_script_env_file" "sync:reload:$service"
			"$pod_script_env_file" "sync:remove:$service"
		fi
		;;
	"sync:prepare:"*)
		service="${command#sync:prepare:}"
		data_dir="/var/main/data"

		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail

			dir="$data_dir/sync/$service"
			file="\${dir}/reload"
			new_file="\${dir}/reloading"

			if [ -f "\$new_file" ]; then
				echo "false"
			elif [ -f "\$file" ]; then
				>&2 touch "\$new_file"
				>&2 rm -f "\$file"

				echo "true"
			else
				echo "false"
			fi
		SHELL
		;;
	"sync:remove:"*)
		service="${command#sync:remove:}"
		data_dir="/var/main/data"

		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" /bin/bash <<-SHELL
			set -eou pipefail

			dir="$data_dir/sync/$service"
			file="\${dir}/reloading"

			if [ -f "\$file" ]; then
				rm -f "\$file"
			fi
		SHELL
		;;
	"run:container:image:"*)
		run_cmd="${command#run:}"
		"$pod_script_container_image_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	"run:nginx:"*)
		run_cmd="${command#run:}"
		"$pod_script_nginx_file" "$run_cmd" ${args[@]+"${args[@]}"}
		;;
	*)
		error "$command: invalid command"
		;;
esac

end="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run-main"|"run"|"stop"|"exec" \
		|"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
		;;
	*)
		>&2 echo -e "${CYAN}$(date '+%F %T') - main - $command - end${NC}"
		>&2 echo -e "${PURPLE}[summary] main - $command - $start - $end${NC}"
		;;
esac
