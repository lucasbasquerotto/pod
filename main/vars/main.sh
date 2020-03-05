#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_file="$pod_layer_dir/main/$var_main_orchestration/main.sh"
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
  error "No command entered (vars)."
fi

shift;

inner_cmd=''
key="$(date '+%Y%m%d_%H%M%S_%3N')"
cmd_path="$(echo "$command" | tr : -)"

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
    backup_local_dir ) backup_local_dir="${OPTARG:-}";;
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
    >&2 echo -e "${CYAN}$(date '+%F %T') - vars - $command - start${NC}"
    ;;
esac

case "$command" in
  "main")
		"$pod_script_env_file" args migrate ${args[@]+"${args[@]}"}
		;;
  "migrate"|"update"|"fast-update"|"setup"|"fast-setup")
    "$pod_script_main_file" "$command" ${args[@]+"${args[@]}"}
    ;;
  "local:prepare")
    env_local_repo="${args[0]}"
    "$ctl_layer_dir/run" dev-cmd bash "/root/w/r/$env_local_repo/run" "${args[@]:1}"
    ;;
  "up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
    
    "$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"args")
    opts=()
    opts+=( "--task_names=$var_main_setup_task_names" )
		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "setup:task:"*)
    prefix="var_setup_task_${command#setup:task:}"
    task_name_verify="${prefix}_task_name_verify"
    task_name_remote="${prefix}_task_name_remote"
    task_name_local="${prefix}_task_name_local"
    task_name_new="${prefix}_task_name_new"
    setup_run_new_task="${prefix}_setup_run_new_task"

    opts=()
    
    opts+=( "--task_name=$command" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )

    opts+=( "--task_name_verify=${!task_name_verify:-}" )
    opts+=( "--task_name_remote=${!task_name_remote:-}" )
    opts+=( "--task_name_local=${!task_name_local:-}" )
    opts+=( "--task_name_new=${!task_name_new:-}" )        
    opts+=( "--setup_run_new_task=${!setup_run_new_task:-}" )

		"$pod_script_main_file" "setup:default" "${opts[@]}"
    ;;
  "setup:verify:"*)
    prefix="var_setup_verify_${command#setup:verify:}"
    setup_dest_dir_to_verify="${prefix}_setup_dest_dir_to_verify"
    
    opts=()
    opts+=( "--setup_dest_dir_to_verify=${!setup_dest_dir_to_verify}" )

    "$pod_script_main_file" "setup:verify" "${opts[@]}" ${args[@]+"${args[@]}"}
    ;;
  "setup:remote:"*)
    prefix="var_setup_remote_${command#setup:remote:}"

    task_kind="${prefix}_task_kind"
    s3_task_name="${prefix}_s3_task_name"
    s3_bucket_name="${prefix}_s3_bucket_name"
    s3_bucket_path="${prefix}_s3_bucket_path"
    restore_dest_dir="${prefix}_restore_dest_dir"
    restore_dest_file="${prefix}_restore_dest_file"
    restore_tmp_dir="${prefix}_restore_tmp_dir"
    restore_local_file="${prefix}_restore_local_file"
    restore_remote_file="${prefix}_restore_remote_file"
    restore_remote_bucket_path_file="${prefix}_restore_remote_bucket_path_file"
    restore_remote_bucket_path_dir="${prefix}_restore_remote_bucket_path_dir"
    restore_is_zip_file="${prefix}_restore_is_zip_file"
    restore_zip_pass="${prefix}_restore_zip_pass"
    restore_zip_inner_dir="${prefix}_restore_zip_inner_dir"
    restore_zip_inner_file="${prefix}_restore_zip_inner_file"

    opts=()
    
    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--restore_zip_tmp_file_name=$cmd_path-$key.zip" )

    opts+=( "--task_kind=${!task_kind:-}" )
    opts+=( "--s3_task_name=${!s3_task_name:-}" )
    opts+=( "--s3_bucket_name=${!s3_bucket_name:-}" )
    opts+=( "--s3_bucket_path=${!s3_bucket_path:-}" )
    opts+=( "--restore_dest_dir=${!restore_dest_dir:-}" )
    opts+=( "--restore_dest_file=${!restore_dest_file:-}" )
    opts+=( "--restore_tmp_dir=${!restore_tmp_dir:-}" )
    opts+=( "--restore_local_file=${!restore_local_file:-}" )
    opts+=( "--restore_remote_file=${!restore_remote_file:-}" )
    opts+=( "--restore_remote_bucket_path_file=${!restore_remote_bucket_path_file:-}" )
    opts+=( "--restore_remote_bucket_path_dir=${!restore_remote_bucket_path_dir:-}" )
    opts+=( "--restore_is_zip_file=${!restore_is_zip_file:-}" )
    opts+=( "--restore_zip_pass=${!restore_zip_pass:-}" )
    opts+=( "--restore_zip_inner_dir=${!restore_zip_inner_dir:-}" )
    opts+=( "--restore_zip_inner_file=${!restore_zip_inner_file:-}" )

		"$pod_script_remote_file" restore "${opts[@]}"
		;;
  "setup:db:"*)
    prefix="var_setup_db_${command#setup:db:}"
    db_task_name="${prefix}_db_task_name"
    
    db_name="${prefix}_db_name"
    db_service="${prefix}_db_service"
    db_user="${prefix}_db_user"
    db_pass="${prefix}_db_pass"
    db_connect_wait_secs="${prefix}_db_connect_wait_secs"
    db_sql_file="${prefix}_db_sql_file"

    opts=()

    opts+=( "--db_name=${!db_name:-}" )
    opts+=( "--db_service=${!db_service:-}" )
    opts+=( "--db_user=${!db_user:-}" )
    opts+=( "--db_pass=${!db_pass:-}" )
    opts+=( "--db_connect_wait_secs=${!db_connect_wait_secs:-}" )
    opts+=( "--db_sql_file=${!db_sql_file:-}" )

		"$pod_script_db_file" "$db_task_name" "${opts[@]}"
		;;
  "backup")
    opts=()

    opts+=( "--task_names=$var_main_backup_task_names" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--backup_local_dir=$var_main_backup_local_base_dir/backup-$key" )
    opts+=( "--backup_delete_old_days=$var_main_backup_delete_old_days" )

		"$pod_script_main_file" backup "${opts[@]}"
		;;
  "backup:task:"*)
    prefix="var_backup_task_${command#backup:task:}"
    task_name_verify="${prefix}_task_name_verify"
    task_name_local="${prefix}_task_name_local"
    task_name_remote="${prefix}_task_name_remote"

    opts=()

    opts+=( "--task_name=$command" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--backup_local_dir=$backup_local_dir" )

    opts+=( "--task_name_verify=${!task_name_verify:-}" )
    opts+=( "--task_name_local=${!task_name_local:-}" )
    opts+=( "--task_name_remote=${!task_name_remote:-}" )

		"$pod_script_main_file" "backup:default" "${opts[@]}"
		;;
  "backup:remote:"*)
    prefix="var_backup_remote_${command#backup:remote:}"
    task_kind="${prefix}_task_kind"
    s3_task_name="${prefix}_s3_task_name"
    s3_bucket_name="${prefix}_s3_bucket_name"
    s3_bucket_path="${prefix}_s3_bucket_path"
    backup_src_base_dir="${prefix}_backup_src_base_dir"
    backup_src_dir="${prefix}_backup_src_dir"
    backup_src_file="${prefix}_backup_src_file"
    backup_zip_file="${prefix}_backup_zip_file"
    backup_bucket_sync_dir="${prefix}_backup_bucket_sync_dir"

    opts=()

    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--backup_local_dir=$backup_local_dir" )

    opts+=( "--task_kind=${!task_kind:-}" )
    opts+=( "--s3_task_name=${!s3_task_name:-}" )
    opts+=( "--s3_bucket_name=${!s3_bucket_name:-}" )
    opts+=( "--s3_bucket_path=${!s3_bucket_path:-}" )
    opts+=( "--backup_src_base_dir=${!backup_src_base_dir:-}" )
    opts+=( "--backup_src_dir=${!backup_src_dir:-}" )
    opts+=( "--backup_src_file=${!backup_src_file:-}" )
    opts+=( "--backup_zip_file=${!backup_zip_file:-}" )
    opts+=( "--backup_bucket_sync_dir=${!backup_bucket_sync_dir:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
    ;;
  "backup:db:"*)
    prefix="var_backup_db_${command#backup:db:}"
    db_task_name="${prefix}_db_task_name"
    
    db_name="${prefix}_db_name"
    db_service="${prefix}_db_service"
    db_user="${prefix}_db_user"
    db_pass="${prefix}_db_pass"
    db_backup_dir="${prefix}_db_backup_dir"
    db_connect_wait_secs="${prefix}_db_connect_wait_secs"

    opts=()

    opts+=( "--db_name=${!db_name:-}" )
    opts+=( "--db_service=${!db_service:-}" )
    opts+=( "--db_user=${!db_user:-}" )
    opts+=( "--db_pass=${!db_pass:-}" )
    opts+=( "--db_backup_dir=${!db_backup_dir:-}" )
    opts+=( "--db_connect_wait_secs=${!db_connect_wait_secs:-}" )

		"$pod_script_db_file" "$db_task_name" "${opts[@]}"
		;;
  "s3:task:"*)
    prefix="var_s3_${command#s3:task:}"
    cli_uploads="${prefix}_cli_uploads"
    cli_cmd_uploads="${prefix}_cli_cmd_uploads"
    service="${prefix}_service"
    endpoint="${prefix}_endpoint"
    bucket_name="${prefix}_bucket_name"
    
    opts=()
    
    opts+=( "--s3_service=${!service:-}" )
    opts+=( "--s3_endpoint=${!endpoint:-}" )
    opts+=( "--s3_bucket_name=${!bucket_name:-}" )
    opts+=( "--s3_src=${s3_src:-}" )
    opts+=( "--s3_dest=${s3_dest:-}" )

    inner_cmd="s3:$cli_uploads:$cli_cmd_uploads:$s3_cmd"
    info "$command - $inner_cmd"
		"$pod_script_s3_file" "$inner_cmd" "${opts[@]}"
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
    >&2 echo -e "${CYAN}$(date '+%F %T') - vars - $command - end${NC}"
    >&2 echo -e "${PURPLE}[summary] vars - $command - $start - $end${NC}"
    ;;
esac
