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
	"u")
    command="upgrade"
    ;;
	"f")
    command="fast-upgrade"
    ;;
	"t")
    command="fast-update"
    ;;
	"s")
    command="args"
    inner_cmd="fast-setup"
    ;;
	"p")
    command="env"
    inner_cmd="prepare"
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
    s3_cmd ) arg_s3_cmd="${OPTARG:-}";;
    s3_src ) arg_s3_src="${OPTARG:-}";;
    s3_src_rel ) arg_s3_src_rel="${OPTARG:-}";;
    s3_dest ) arg_s3_dest="${OPTARG:-}";;
    s3_dest_rel ) arg_s3_dest_rel="${OPTARG:-}";;
    s3_file ) arg_s3_file="${OPTARG:-}";;
    backup_local_dir ) arg_backup_local_dir="${OPTARG:-}";;
		backup_delete_old_days ) arg_backup_delete_old_days="${OPTARG:-}";;
    db_task_name ) arg_db_task_name="${OPTARG:-}";; 
    env_local_repo ) arg_env_local_repo="${OPTARG:-}";; 
    ctl_layer_dir ) arg_ctl_layer_dir="${OPTARG:-}";; 
    setup_dest_base_dir ) arg_setup_dest_base_dir="${OPTARG:-}";;
    backup_src_base_dir ) arg_backup_src_base_dir="${OPTARG:-}";;
    db_task_base_dir ) arg_db_task_base_dir="${OPTARG:-}";;
    db_sql_file_name ) arg_db_sql_file_name="${OPTARG:-}";;
		opts ) arg_opts=( "${@:OPTIND}" ); break;; 
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
  "env")
    "$pod_script_env_file" "$inner_cmd" ${args[@]+"${args[@]}"}
    ;;
  "upgrade"|"fast-upgrade"|"update"|"fast-update")
		"$pod_script_env_file" args "$command" ${args[@]+"${args[@]}"}
		;;
  "stop-to-upgrade")
		"$pod_script_env_file" stop ${args[@]+"${args[@]}"}
		;;
  "setup"|"fast-setup")
    "$pod_script_main_file" "$command" ${args[@]+"${args[@]}"}
    ;;
  "local:prepare")
    "$arg_ctl_layer_dir/run" dev-cmd bash "/root/w/r/$arg_env_local_repo/run" "${arg_opts[@]}"
    ;;
  "up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")

    if [ -n "${var_orchestration_main_file:-}" ] && [ -z "${ORCHESTRATION_MAIN_FILE:-}" ]; then
      export ORCHESTRATION_MAIN_FILE="$var_orchestration_main_file"
    fi
    
    if [ -n "${var_orchestration_run_file:-}" ] && [ -z "${ORCHESTRATION_RUN_FILE:-}" ]; then
      export ORCHESTRATION_RUN_FILE="$var_orchestration_run_file"
    fi
    
    "$pod_script_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
	"args")
    if [ -n "${var_orchestration_main_file:-}" ] && [ -z "${ORCHESTRATION_MAIN_FILE:-}" ]; then
      export ORCHESTRATION_MAIN_FILE="$var_orchestration_main_file"
    fi
    
    if [ -n "${var_orchestration_run_file:-}" ] && [ -z "${ORCHESTRATION_RUN_FILE:-}" ]; then
      export ORCHESTRATION_RUN_FILE="$var_orchestration_run_file"
    fi

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
    setup_dest_base_dir="${prefix}_setup_dest_base_dir"

    opts=()
    
    opts+=( "--task_name=$command" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )

    opts+=( "--setup_dest_base_dir=${!setup_dest_base_dir}" )
    
    opts+=( "--task_name_verify=${!task_name_verify:-}" )
    opts+=( "--task_name_remote=${!task_name_remote:-}" )
    opts+=( "--task_name_local=${!task_name_local:-}" )
    opts+=( "--task_name_new=${!task_name_new:-}" )        
    opts+=( "--setup_run_new_task=${!setup_run_new_task:-}" )

		"$pod_script_main_file" "setup:default" "${opts[@]}"
    ;;
  "setup:verify:db:"*)
    ctx="${command#setup:verify:db:}"
    prefix="var_setup_verify_${ctx}"
    db_task_name="${prefix}_db_task_name"
		"$pod_script_env_file" "db:task:$ctx" --db_task_name="${!db_task_name}"
		;;
  "setup:verify:default:"*)
    prefix="var_setup_verify_${command#setup:verify:default:}"
    setup_dest_dir_to_verify="${prefix}_setup_dest_dir_to_verify"
    
    opts=()
    opts+=( "--setup_dest_dir_to_verify=${!setup_dest_dir_to_verify}" )

    "$pod_script_main_file" "setup:verify" "${opts[@]}" ${args[@]+"${args[@]}"}
    ;;
  "setup:remote:default:"*)
    prefix="var_setup_remote_${command#setup:remote:default:}"

    task_kind="${prefix}_task_kind"
    task_name_s3="${prefix}_task_name_s3"
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
    opts+=( "--restore_dest_base_dir=${arg_setup_dest_base_dir}" )

    opts+=( "--restore_tmp_dir=${!restore_tmp_dir}" )

    opts+=( "--task_kind=${!task_kind:-}" )
    opts+=( "--task_name_s3=${!task_name_s3:-}" )
    opts+=( "--restore_dest_file=${!restore_dest_file:-}" )
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
  "setup:local:db:"*)
    ctx="${command#setup:local:db:}"
    prefix="var_setup_local_${ctx}"
    db_task_name="${prefix}_db_task_name"
    db_sql_file_name="${prefix}_db_sql_file_name"
    
    opts=()

    opts+=( "--db_task_base_dir=${arg_setup_dest_base_dir}" )

    opts+=( "--db_task_name=${!db_task_name}" )
    opts+=( "--db_sql_file_name=${!db_sql_file_name}" )

		"$pod_script_env_file" "db:task:$ctx" "${opts[@]}"
		;;
  "backup")
    opts=()

    opts+=( "--task_names=$var_main_backup_task_names" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--backup_local_base_dir=$var_main_backup_local_base_dir" )
    opts+=( "--backup_local_dir=$var_main_backup_local_base_dir/backup-$key" )
    opts+=( "--backup_delete_old_days=$var_main_backup_delete_old_days" )

		"$pod_script_main_file" backup "${opts[@]}"
		;;
  "backup:task:"*)
    prefix="var_backup_task_${command#backup:task:}"
    task_name_verify="${prefix}_task_name_verify"
    task_name_local="${prefix}_task_name_local"
    task_name_remote="${prefix}_task_name_remote"
    backup_src_base_dir="${prefix}_backup_src_base_dir"
    backup_local_static_dir="${prefix}_backup_local_static_dir"
    backup_delete_old_days="${prefix}_backup_delete_old_days"    

    opts=()

    opts+=( "--task_name=$command" )
    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    
    opts+=( "--backup_local_dir=${!backup_local_static_dir:-$arg_backup_local_dir}" )
    opts+=( "--backup_delete_old_days=${!backup_delete_old_days:-$arg_backup_delete_old_days}" )    

    opts+=( "--task_name_verify=${!task_name_verify:-}" )
    opts+=( "--task_name_local=${!task_name_local:-}" )
    opts+=( "--task_name_remote=${!task_name_remote:-}" )
    opts+=( "--backup_src_base_dir=${!backup_src_base_dir}" )

		"$pod_script_main_file" "backup:default" "${opts[@]}"
		;;
  "backup:remote:default:"*)
    prefix="var_backup_remote_${command#backup:remote:default:}"
    task_kind="${prefix}_task_kind"
    task_name_s3="${prefix}_task_name_s3"
    backup_src_dir="${prefix}_backup_src_dir"
    backup_src_file="${prefix}_backup_src_file"
    backup_zip_file="${prefix}_backup_zip_file"
    backup_bucket_static_dir="${prefix}_backup_bucket_static_dir"
    backup_bucket_sync_dir="${prefix}_backup_bucket_sync_dir"

    opts=()

    opts+=( "--toolbox_service=$var_main_toolbox_service" )
    opts+=( "--backup_src_base_dir=$arg_backup_src_base_dir" )
    opts+=( "--backup_local_dir=$arg_backup_local_dir" )

    opts+=( "--task_kind=${!task_kind}" )
    opts+=( "--task_name_s3=${!task_name_s3:-}" )
    opts+=( "--backup_src_dir=${!backup_src_dir:-}" )
    opts+=( "--backup_src_file=${!backup_src_file:-}" )
    opts+=( "--backup_zip_file=${!backup_zip_file:-}" )
    opts+=( "--backup_bucket_static_dir=${!backup_bucket_static_dir:-}" )
    opts+=( "--backup_bucket_sync_dir=${!backup_bucket_sync_dir:-}" )

		"$pod_script_remote_file" backup "${opts[@]}"
    ;;
  "backup:local:db:"*)
    ctx="${command#backup:local:db:}"
    prefix="var_backup_local_${ctx}"
    db_task_name="${prefix}_db_task_name"
    db_sql_file_name="${prefix}_db_sql_file_name"
    
    opts=()

    opts+=( "--db_task_base_dir=${arg_backup_src_base_dir}" )

    opts+=( "--db_task_name=${!db_task_name}" )
    opts+=( "--db_sql_file_name=${!db_sql_file_name}" )

		"$pod_script_env_file" "db:task:$ctx" "${opts[@]}"
		;;
  "db:task:"*)
    prefix="var_db_${command#db:task:}"
    
    db_name="${prefix}_db_name"
    db_service="${prefix}_db_service"
    db_user="${prefix}_db_user"
    db_pass="${prefix}_db_pass"
    db_connect_wait_secs="${prefix}_db_connect_wait_secs"

    opts=()

    opts+=( "--db_task_base_dir=${arg_db_task_base_dir:-}" )
    opts+=( "--db_sql_file_name=${arg_db_sql_file_name:-}" )

    opts+=( "--db_name=${!db_name:-}" )
    opts+=( "--db_service=${!db_service:-}" )
    opts+=( "--db_user=${!db_user:-}" )
    opts+=( "--db_pass=${!db_pass:-}" )
    opts+=( "--db_connect_wait_secs=${!db_connect_wait_secs:-}" )

		"$pod_script_db_file" "$arg_db_task_name" "${opts[@]}"
		;;
  "s3:task:"*)
    prefix="var_s3_${command#s3:task:}"
    cli="${prefix}_cli"
    cli_cmd="${prefix}_cli_cmd"
    service="${prefix}_service"
    endpoint="${prefix}_endpoint"
    bucket_name="${prefix}_bucket_name"
    bucket_path="${prefix}_bucket_path"
  
    bucket_prefix="${!bucket_name:-}"

    if [ -n "${!bucket_path:-}" ];then
      bucket_prefix="${!bucket_name}/${!bucket_path}"
    fi

    s3_src="${arg_s3_src:-}"

    if [ -n "${arg_s3_src_rel:-}" ];then
      s3_src="$bucket_prefix/$arg_s3_src_rel"
      s3_src=$(echo "$s3_src" | tr -s /)
      s3_src="s3://$s3_src"
    fi

    s3_dest="${arg_s3_dest:-}"

    if [ -n "${arg_s3_dest_rel:-}" ];then
      s3_dest="$bucket_prefix/$arg_s3_dest_rel"
      s3_dest=$(echo "$s3_dest" | tr -s /)
      s3_dest="s3://$s3_dest"
    fi	
		
    s3_opts=()

    if [ -n "${arg_s3_file:-}" ]; then
      s3_opts=( --exclude "*" --include "$arg_s3_file" )
    fi
    
    opts=()
    
    opts+=( "--s3_service=${!service:-}" )
    opts+=( "--s3_endpoint=${!endpoint:-}" )
    opts+=( "--s3_bucket_name=${!bucket_name:-}" )

    opts+=( "--s3_src=${s3_src:-}" )
    opts+=( "--s3_dest=${s3_dest:-}" )
    opts+=( "--s3_opts" )
    opts+=( "${s3_opts[@]}" )

    inner_cmd="s3:${!cli}:${!cli_cmd}:$arg_s3_cmd"
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
