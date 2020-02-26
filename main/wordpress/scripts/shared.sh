#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

pod_script_run_file="$pod_layer_dir/main/compose/main.sh"
pod_script_main_file="$pod_layer_dir/main/scripts/main.sh"
pod_script_db_file="$pod_layer_dir/main/scripts/db.sh"
pod_script_remote_file="$pod_layer_dir/main/scripts/remote.sh"

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
			error "[$command] command not specified"
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

case "$command" in
  "args"|"args:"*)
    while getopts ':-:' OPT; do
      if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
        OPT="${OPTARG%%=*}"       # extract long option name
        OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
      fi
      case "$OPT" in
        task_name ) task_name="${OPTARG:-}";;
        setup_restored_path ) setup_restored_path="${OPTARG:-}";;
        ??* ) ;;  # bad long option
        \? )  ;;  # bad short option (error reported via getopts)
      esac
    done
    shift $((OPTIND-1))
		;;
esac
  
start="$(date '+%F %T')"

case "$command" in
  "setup:new:wp:db"|"upgrade")
    echo -e "${CYAN}$(date '+%F %T') - env (shared) - $command - start${NC}"
    ;;
esac

case "$command" in
  "main")
		"$pod_script_env_file" args migrate "$@"
		;;
  "setup:task:wp:uploads"|"setup:task:wp:db")
    "$pod_script_env_file" "args:${command}" "setup:default" "$@"
    ;;
  "setup:verify:wp:uploads")
    "$pod_script_main_file" "setup:verify" "$@"
    ;;
  "setup:remote:wp:uploads"|"setup:remote:wp:db")
    "$pod_script_env_file" "args:${command}" restore "$@"
    ;;
  "setup:verify:wp:db")
		"$pod_script_env_file" "args:db:wp" "setup:verify:mysql" "$@"
		;;
  "setup:local:file:wp:db")
		"$pod_script_env_file" "args:db:wp" "setup:local:file:mysql" "$@"
		;;
  "backup")
    "$pod_script_env_file" "args:backup" "$command" "$@"
    ;;
  "backup:task:wp:uploads"|"backup:task:wp:db")
    "$pod_script_env_file" "args:main:${command}" "backup:default" "$@"
    ;;
  "backup:remote:wp:uploads"|"backup:remote:wp:db")
    "$pod_script_env_file" "args:${command}" backup "$@"
    ;;
  "backup:local:wp")
		"$pod_script_env_file" "args:db:wp" "backup:local:mysql" "$@"
		;;
	"migrate"|"update"|"fast-update"|"setup"|"fast-setup")
    "$pod_script_main_file" "$command" "$@"
    ;;
	"up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec" \
    |"restart"|"logs"|"ps"|"ps-run"|"sh"|"bash")
    
    "$pod_script_run_file" "$command" "$@"
		;;
  "setup:new:wp:db")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    echo -e "${CYAN}$(date '+%F %T') - $command - installation${NC}"
    "$pod_script_run_file" run wordpress \
      wp --allow-root core install \
      --url="$var_setup_url" \
      --title="$var_setup_title" \
      --admin_user="$var_setup_admin_user" \
      --admin_password="$var_setup_admin_password" \
      --admin_email="$var_setup_admin_email"

    if [ ! -z "$var_setup_local_seed_data" ] || [ ! -z "$var_setup_remote_seed_data" ]; then
      echo -e "${CYAN}$(date '+%F %T') - $command - upgrade...${NC}"
      "$pod_script_env_file" upgrade "$@"

      if [ ! -z "$var_setup_local_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %T') - $command - import local seed data${NC}"
        "$pod_script_run_file" run wordpress \
          wp --allow-root import ./"$var_setup_local_seed_data" --authors=create
      fi

      if [ ! -z "$var_setup_remote_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %T') - $command - import remote seed data${NC}"
        "$pod_script_run_file" run wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$var_setup_remote_seed_data' \
          && wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
          && rm -f ./tmp/tmp-seed-data.xml"
      fi
    fi
    ;;
  "upgrade")
    >&2 echo -e "${CYAN}$(date '+%F %T') - upgrade (app) - start container${NC}"
    "$pod_script_run_file" up wordpress

    "$pod_script_run_file" exec-nontty wordpress /bin/bash <<-SHELL
			set -eou pipefail

      >&2 echo -e "${CYAN}$(date '+%F %T') - upgrade (app) - update database${NC}"
      wp --allow-root core update-db

      >&2 echo -e "${CYAN}$(date '+%F %T') - upgrade (app) - activate plugins${NC}"
      wp --allow-root plugin activate --all

      if [ ! -z "$var_old_domain_host" ] && [ ! -z "$var_new_domain_host" ]; then
        >&2 echo -e "${CYAN}$(date '+%F %T') - upgrade (app) - update domain${NC}"
        wp --allow-root search-replace "$var_old_domain_host" "$var_new_domain_host"
      fi
		SHELL
    ;;
  "args")
    opts=()
    opts+=( "--task_names=${var_setup_task_names:-}" )
		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:backup")
    opts=()
    opts+=( "--task_names=${var_backup_task_names:-}" )
		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:setup:task:wp:uploads")
    opts=()
    
    opts+=( "--task_name=$task_name" )
    opts+=( "--task_name_verify=setup:verify:wp:uploads" )
    opts+=( "--task_name_remote=setup:remote:wp:uploads" )

    opts+=( "--setup_service=${var_setup_service:-}" )
    opts+=( "--setup_dest_dir=${var_uploads_service_dir:-}" )

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:setup:remote:wp:uploads")
    opts=()
    
    opts+=( "--task_short_name=wp-uploads" )
    opts+=( "--task_kind=dir" )
    opts+=( "--bucket_name=${var_backup_bucket_name:-}" )
    opts+=( "--bucket_path=${var_backup_bucket_path:-}" )
    opts+=( "--task_service=${var_setup_service:-}" )
    opts+=( "--tmp_dir=${var_uploads_main_dir:-}" )
    opts+=( "--s3_endpoint=${var_s3_endpoint:-}" )
    opts+=( "--use_aws_s3=${var_use_aws_s3:-}" )
    opts+=( "--use_s3cmd=${var_use_s3cmd:-}" )

    opts+=( "--restore_dest_dir=${var_uploads_service_dir:-}" )
    opts+=( "--restore_local_zip_file=${var_setup_local_uploads_zip_file:-}" )
    opts+=( "--restore_remote_zip_file=${var_setup_remote_uploads_zip_file:-}" )
    opts+=( "--restore_remote_bucket_path_dir=${var_setup_remote_bucket_path_uploads_dir:-}" )
    opts+=( "--restore_remote_bucket_path_file=${var_setup_remote_bucket_path_uploads_file:-}" )
    opts+=( "--restore_zip_inner_dir=uploads" )

		"$pod_script_remote_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:setup:task:wp:db")
    opts=()
    
    opts+=( "--task_name=$task_name" )
    opts+=( "--task_name_verify=setup:verify:wp:db" )
    opts+=( "--task_name_remote=setup:remote:wp:db" )
    opts+=( "--task_name_local=setup:local:file:wp:db" )
    opts+=( "--task_name_new=setup:new:wp:db" )
        
    opts+=( "--setup_service=${var_setup_service:-}" )
    opts+=( "--setup_dest_dir=${var_db_restore_dir:-}" )
    opts+=( "--setup_run_new_task=${var_setup_run_new_task_wp_db:-}" )

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:setup:remote:wp:db")
    opts=()
    
    opts+=( "--task_short_name=wp-db" )
    opts+=( "--task_kind=file" )
    opts+=( "--bucket_name=${var_backup_bucket_name:-}" )
    opts+=( "--bucket_path=${var_backup_bucket_path:-}" )
    opts+=( "--task_service=${var_setup_service:-}" )
    opts+=( "--tmp_dir=${var_db_restore_dir:-}" )
    opts+=( "--s3_endpoint=${var_s3_endpoint:-}" )
    opts+=( "--use_aws_s3=${var_use_aws_s3:-}" )
    opts+=( "--use_s3cmd=${var_use_s3cmd:-}" )

    opts+=( "--restore_dest_dir=${var_db_restore_dir:-}" )
    opts+=( "--restore_local_zip_file=${var_setup_local_db_zip_file:-}" )
    opts+=( "--restore_remote_zip_file=${var_setup_remote_db_zip_file:-}" )
    opts+=( "--restore_remote_bucket_path_dir=${var_setup_remote_bucket_path_db_dir:-}" )
    opts+=( "--restore_remote_bucket_path_file=${var_setup_remote_bucket_path_db_file:-}" )
    opts+=( "--restore_zip_inner_file=$var_db_name.sql" )

		"$pod_script_remote_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:backup:task:wp:uploads")
    opts=()

    opts+=( "--task_name=$task_name" )
    opts+=( "--task_name_remote=backup:remote:wp:uploads" )

    opts+=( "--backup_service=${var_backup_service:-}" )
    opts+=( "--backup_base_dir=${var_main_backup_base_dir:-}" )
    opts+=( "--backup_delete_old_days=${var_backup_delete_old_days:-}" )

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:backup:remote:wp:uploads")
    opts=()

    opts+=( "--task_short_name=wp-uploads" )
    opts+=( "--task_kind=dir" )
    opts+=( "--bucket_name=${var_backup_bucket_name:-}" )
    opts+=( "--bucket_path=${var_backup_bucket_path:-}" )
    opts+=( "--task_service=${var_backup_service:-}" )
    opts+=( "--tmp_dir=${var_uploads_main_dir:-}" )
    opts+=( "--s3_endpoint=${var_s3_endpoint:-}" )
    opts+=( "--use_aws_s3=${var_use_aws_s3:-}" )
    opts+=( "--use_s3cmd=${var_use_s3cmd:-}" )

    opts+=( "--backup_src_dir=${var_uploads_service_dir:-}" )
    opts+=( "--backup_base_dir=${var_main_backup_base_dir:-}" )
    opts+=( "--backup_bucket_sync_dir=${var_backup_bucket_uploads_sync_dir:-}" )

		"$pod_script_remote_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:backup:task:wp:db")
    opts=()

    opts+=( "--task_name=$task_name" )
    opts+=( "--task_name_local=backup:local:wp" )
    opts+=( "--task_name_remote=backup:remote:wp:db" )

    opts+=( "--backup_service=${var_backup_service:-}" )
    opts+=( "--backup_base_dir=${var_main_backup_base_dir:-}" )
    opts+=( "--backup_delete_old_days=${var_backup_delete_old_days:-}" )

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  
  "args:backup:remote:wp:db")
    opts=()

    opts+=( "--task_short_name=wp-db" )
    opts+=( "--task_kind=file" )
    opts+=( "--bucket_name=${var_backup_bucket_name:-}" )
    opts+=( "--bucket_path=${var_backup_bucket_path:-}" )
    opts+=( "--task_service=${var_backup_service:-}" )
    opts+=( "--tmp_dir=${var_db_backup_dir:-}" )
    opts+=( "--s3_endpoint=${var_s3_endpoint:-}" )
    opts+=( "--use_aws_s3=${var_use_aws_s3:-}" )
    opts+=( "--use_s3cmd=${var_use_s3cmd:-}" )
    
    opts+=( "--backup_src_dir=${var_db_backup_dir:-}" )
    opts+=( "--backup_src_file=${var_db_name:-}.sql" )
    opts+=( "--backup_base_dir=${var_main_backup_base_dir:-}" )
    opts+=( "--backup_bucket_sync_dir=${var_backup_bucket_uploads_sync_dir:-}" )

		"$pod_script_remote_file" "$inner_cmd" "${opts[@]}"
		;;
  
  "args:db:wp")
    opts=()

    opts+=( "--db_name=${var_db_name:-}" )
    opts+=( "--db_service=${var_db_service:-}" )
    opts+=( "--db_user=${var_db_user:-}" )
    opts+=( "--db_pass=${var_db_pass:-}" )
    opts+=( "--db_backup_dir=${var_db_backup_dir:-}" )
    opts+=( "--db_sql_file=${setup_restored_path:-}" )

		"$pod_script_db_file" "$inner_cmd" "${opts[@]}"
    ;;
  *)
		error "$command: invalid command"
    ;;
esac

end="$(date '+%F %T')"

case "$command" in
  "setup:new:wp:db"|"upgrade")
    echo -e "${CYAN}$(date '+%F %T') - env (shared) - $command - end${NC}"
    echo -e "${CYAN}env (shared) - $command - $start - $end${NC}"
    ;;
esac