#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_env_shared_exec_file="$pod_layer_dir/$var_scripts_dir/shared.exec.sh"

pod_script_run_file="$pod_layer_dir/main/compose/main.sh"
pod_script_main_file="$pod_layer_dir/main/scripts/main.sh"
pod_script_db_file="$pod_layer_dir/main/scripts/db.sh"
pod_script_remote_file="$pod_layer_dir/main/scripts/remote.sh"
pod_script_s3_file="$pod_layer_dir/main/scripts/s3.sh"

CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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

if [ -z "$pod_layer_dir" ] || [ "$pod_layer_dir" = "/" ]; then
  error "This project must not be in the '/' directory"
fi

command="${1:-}"

if [ -z "$command" ]; then
  error "No command entered (env - shared)."
fi

shift;

inner_cmd=''

case "$command" in
  "args"|"args:"*)
    inner_cmd="${1:-}"

		if [ -z "$inner_cmd" ]; then
			error "$command: inner command not specified"
		fi

    shift;
    ;;
	"m")
    command="args"
    inner_cmd="migrate"
    ;;
	"u")
    command="args"
    inner_cmd="update"
    ;;
	"f")
    command="args"
    inner_cmd="fast-update"
    ;;
	"s")
    command="args"
    inner_cmd="fast-setup"
    ;;
esac

args=("$@")

while getopts ':-:' OPT; do
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case "$OPT" in
    s3_cmd ) s3_cmd="${OPTARG:-}";;
    s3_src ) s3_src="${OPTARG:-}";;
    s3_dest ) s3_dest="${OPTARG:-}";;
    ??* ) ;;  # bad long option
    \? )  ;;  # bad short option (error reported via getopts)
  esac
done
shift $((OPTIND-1))

start="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
    ;;
  *)
    >&2 echo -e "${CYAN}$(date '+%F %T') - env (shared) - $command - start${NC}"
    ;;
esac

case "$command" in
  "main")
		"$pod_script_env_file" args migrate ${args[@]+"${args[@]}"}
		;;
  "migrate"|"update"|"fast-update"|"setup"|"fast-setup")
    "$pod_script_main_file" "$command" ${args[@]+"${args[@]}"}
    ;;
	"upgrade")
    opts=()

    opts+=( "--setup_url=$var_setup_url" )
    opts+=( "--setup_title=$var_setup_title" )
    opts+=( "--setup_admin_user=$var_setup_admin_user" )
    opts+=( "--setup_admin_password=$var_setup_admin_password" )
    opts+=( "--setup_admin_email=$var_setup_admin_email" )
    opts+=( "--setup_local_seed_data=${var_setup_local_seed_data:-}" )
    opts+=( "--setup_remote_seed_data=${var_setup_remote_seed_data:-}" )
    opts+=( "--old_domain_host=${var_old_domain_host:-}" )
    opts+=( "--new_domain_host=${var_new_domain_host:-}" )

    "$pod_env_shared_exec_file" upgrade "${opts[@]}"
    ;;
  "up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
    
    "$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"args")
    opts=()
    opts+=( "--task_names=$var_setup_task_names" )
		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "setup:task:wp:uploads")
    opts=()
    
    opts+=( "--task_name=$command" )
    opts+=( "--task_name_verify=setup:verify:wp:uploads" )
    opts+=( "--task_name_remote=setup:remote:wp:uploads" )

    opts+=( "--toolbox_service=$var_toolbox_service" )

		"$pod_script_main_file" "setup:default" "${opts[@]}"
    ;;
  "setup:verify:wp:uploads")
    opts=()
    opts+=( "--setup_dest_dir_to_verify=$var_wp_uploads_base_dir/$var_wp_uploads_dir" )
    "$pod_script_main_file" "setup:verify" "${opts[@]}" ${args[@]+"${args[@]}"}
    ;;
  "setup:remote:wp:uploads")
    opts=()
    
    opts+=( "--task_short_name=wp-uploads" )
    opts+=( "--task_kind=dir" )
    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--s3_task_name=s3:task:wp:uploads" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_uploads" )
    opts+=( "--s3_bucket_path=${var_s3_bucket_path_uploads:-}" )

    opts+=( "--restore_dest_dir=$var_wp_uploads_base_dir/$var_wp_uploads_dir" )
    opts+=( "--restore_tmp_dir=$var_uploads_restore_tmp_dir" )
    opts+=( "--restore_local_file=${var_setup_local_uploads_file:-}" )
    opts+=( "--restore_remote_file=${var_setup_remote_uploads_file:-}" )
    opts+=( "--restore_remote_bucket_path_file=${var_setup_remote_bucket_path_uploads_file:-}" )
    opts+=( "--restore_remote_bucket_path_dir=${var_setup_remote_bucket_path_uploads_dir:-}" )
    opts+=( "--restore_is_zip_file=${var_setup_uploads_is_zip_file:-}" )
    opts+=( "--restore_zip_pass=${var_setup_uploads_zip_pass:-}" )
    opts+=( "--restore_zip_inner_dir=${var_setup_uploads_zip_inner_dir:-}" )

		"$pod_script_remote_file" restore "${opts[@]}"
		;;
  "setup:task:wp:db")
    opts=()
    
    opts+=( "--task_name=$command" )
    opts+=( "--task_name_verify=setup:verify:wp:db" )
    opts+=( "--task_name_remote=setup:remote:wp:db" )
    opts+=( "--task_name_local=setup:local:wp:db" )
    opts+=( "--task_name_new=setup:new:wp:db" )
        
    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--setup_run_new_task=${var_setup_run_new_task_wp_db:-}" )

		"$pod_script_main_file" "setup:default" "${opts[@]}"
		;;
  "setup:verify:wp:db")
		"$pod_script_env_file" "args:db:wp" "restore:verify:mysql" ${args[@]+"${args[@]}"}
		;;
  "setup:remote:wp:db")
    opts=()
    
    opts+=( "--task_short_name=wp-db" )
    opts+=( "--task_kind=file" )
    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--s3_task_name=s3:task:wp:db" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_db" )
    opts+=( "--s3_bucket_path=${var_s3_bucket_path_db:-}" )

    opts+=( "--restore_dest_dir=$var_db_restore_dir" )
    opts+=( "--restore_dest_file=$var_db_name.sql" )
    opts+=( "--restore_tmp_dir=$var_db_restore_tmp_dir" )
    opts+=( "--restore_local_file=${var_setup_local_db_file:-}" )
    opts+=( "--restore_remote_file=${var_setup_remote_db_file:-}" )
    opts+=( "--restore_remote_bucket_path_file=${var_setup_remote_bucket_path_db_file:-}" )
    opts+=( "--restore_remote_bucket_path_dir=${var_setup_remote_bucket_path_db_dir:-}" )
    opts+=( "--restore_is_zip_file=${var_setup_db_is_zip_file:-}" )
    opts+=( "--restore_zip_pass=${var_setup_db_zip_pass:-}" )
    opts+=( "--restore_zip_inner_file=${var_setup_db_zip_inner_file:-}" )

		"$pod_script_remote_file" restore "${opts[@]}"
    ;;
  "setup:local:wp:db")
		"$pod_script_env_file" "args:db:wp" "restore:file:mysql" ${args[@]+"${args[@]}"}
		;;
  "setup:new:wp:db")
    "$pod_env_shared_exec_file" "setup:new:wp:db" ${args[@]+"${args[@]}"}
    ;;
  "backup")
		"$pod_script_main_file" backup --task_names="$var_backup_task_names"
		;;
  "backup:task:wp:uploads")
    opts=()

    opts+=( "--task_name=$command" )
    opts+=( "--task_name_remote=backup:remote:wp:uploads" )

    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--backup_tmp_base_dir=$var_backup_tmp_base_dir" )
    opts+=( "--backup_delete_old_days=$var_backup_delete_old_days" )

		"$pod_script_main_file" "backup:default" "${opts[@]}"
		;;
  "backup:remote:wp:uploads")
    opts=()

    opts+=( "--task_short_name=wp-uploads" )
    opts+=( "--task_kind=dir" )
    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--s3_task_name=s3:task:wp:uploads" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_uploads" )
    opts+=( "--s3_bucket_path=${var_s3_bucket_path_uploads:-}" )

    opts+=( "--backup_src_base_dir=$var_wp_uploads_base_dir" )
    opts+=( "--backup_src_dir=$var_wp_uploads_dir" )
    opts+=( "--backup_tmp_base_dir=$var_backup_tmp_base_dir" )
    opts+=( "--backup_bucket_sync_dir=${var_backup_bucket_uploads_sync_dir:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
    ;;
  "backup:task:wp:db")
    opts=()

    opts+=( "--task_name=$command" )
    opts+=( "--task_name_local=backup:local:wp" )
    opts+=( "--task_name_remote=backup:remote:wp:db" )

    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--backup_tmp_base_dir=$var_backup_tmp_base_dir" )
    opts+=( "--backup_delete_old_days=$var_backup_delete_old_days" )

		"$pod_script_main_file" "backup:default" "${opts[@]}"
    ;;
  "backup:remote:wp:db")
    opts=()

    opts+=( "--task_short_name=wp-db" )
    opts+=( "--task_kind=file" )
    opts+=( "--toolbox_service=$var_toolbox_service" )
    opts+=( "--s3_task_name=s3:task:wp:db" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_db" )
    opts+=( "--s3_bucket_path=${var_s3_bucket_path_db:-}" )
    
    opts+=( "--backup_src_base_dir=$var_db_backup_dir" )
    opts+=( "--backup_src_file=$var_db_name.sql" )
    opts+=( "--backup_tmp_base_dir=$var_backup_tmp_base_dir" )
    opts+=( "--backup_bucket_sync_dir=${var_backup_bucket_db_sync_dir:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
    ;;
  "backup:local:wp")
		"$pod_script_env_file" "args:db:wp" "backup:file:mysql" ${args[@]+"${args[@]}"}
		;;
  "s3:task:wp:uploads")
    opts=()
    
    opts+=( "--s3_service=$var_s3_service" )
    opts+=( "--s3_endpoint=$var_s3_endpoint_uploads" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_uploads" )
    opts+=( "--s3_src=${s3_src:-}" )
    opts+=( "--s3_dest=${s3_dest:-}" )

    inner_cmd="s3:$var_s3_cli:$var_s3_cli_cmd:$s3_cmd"
    info "$command - $inner_cmd"
		"$pod_script_s3_file" "$inner_cmd" "${opts[@]}"
		;;
  "s3:task:wp:db")
    opts=()
    
    opts+=( "--s3_service=$var_s3_service" )
    opts+=( "--s3_endpoint=$var_s3_endpoint_db" )
    opts+=( "--s3_bucket_name=$var_s3_bucket_name_db" )
    opts+=( "--s3_src=${s3_src:-}" )
    opts+=( "--s3_dest=${s3_dest:-}" )

    inner_cmd="s3:$var_s3_cli:$var_s3_cli_cmd:$s3_cmd"
    info "$command - $inner_cmd"
		"$pod_script_s3_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:db:wp")
    opts=()

    opts+=( "--db_name=$var_db_name" )
    opts+=( "--db_service=$var_db_service" )
    opts+=( "--db_user=$var_db_user" )
    opts+=( "--db_pass=$var_db_pass" )
    opts+=( "--db_backup_dir=$var_db_backup_dir" )
    opts+=( "--db_connect_wait_secs=$var_db_connect_wait_secs" )
    opts+=( "--db_sql_file=/$var_db_restore_dir/$var_db_name.sql" )    

		"$pod_script_db_file" "$inner_cmd" "${opts[@]}"
    ;;
  *)
		error "$command: invalid command"
    ;;
esac

end="$(date '+%F %T')"

case "$command" in
	"up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
    ;;
  *)
    >&2 echo -e "${CYAN}$(date '+%F %T') - env (shared) - $command - end${NC}"
    >&2 echo -e "${PURPLE}[summary] env (shared) - $command - $start - $end${NC}"
    ;;
esac
