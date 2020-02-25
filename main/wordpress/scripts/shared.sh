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

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function error {
	msg="$(date '+%F %X') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
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
  "main"|"args"|"args:"*)
    die() { error "$*"; }  # complain to STDERR and exit with error
    needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

    while getopts ':-:' OPT; do
      if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
        OPT="${OPTARG%%=*}"       # extract long option name
        OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
      fi
      case "$OPT" in
        uploads_task_name ) needs_arg; uploads_task_name="$OPTARG";;
        db_task_name ) needs_arg; db_task_name="$OPTARG";; 
        db_sql_file ) needs_arg; db_sql_file="$OPTARG" ;;
        ??* ) ;;  # bad long option
        \? )  ;;  # bad short option (error reported via getopts)
      esac
    done
    shift $((OPTIND-1))
		;;
esac
  
start="$(date '+%F %X')"

case "$command" in
  "setup:db:new"|"deploy")
    echo -e "${CYAN}$(date '+%F %X') - env (shared) - $command - start${NC}"
    ;;
esac

case "$command" in
  "main")
		"$pod_script_env_file" args migrate "$@"
		;;
  "deploy")
    echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - remove old container${NC}"
    "$pod_script_run_file" rm wordpress

    echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update database${NC}"
    "$pod_script_run_file" run --rm wordpress wp --allow-root \
        core update-db

    echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - activate plugins${NC}"
    "$pod_script_run_file" run --rm wordpress wp --allow-root \
        plugin activate --all

    if [ ! -z "$var_old_domain_host" ] && [ ! -z "$var_new_domain_host" ]; then
        echo -e "${CYAN}$(date '+%F %X') - upgrade (app) - update domain${NC}"
        "$pod_script_run_file" run --rm wordpress wp --allow-root \
            search-replace "$var_old_domain_host" "$var_new_domain_host"
    fi
    ;;
  "args")
    opts=()

    if [ ! -z "${var_setup_uploads_task_names:-}" ]; then
      opts+=( "--setup_uploads_task_names=${var_setup_uploads_task_names:-}" )
    fi
    if [ ! -z "${var_setup_dbs_task_names:-}" ]; then
      opts+=( "--setup_dbs_task_names=${var_setup_dbs_task_names:-}" )
    fi
    
    if [ ${#@} -ne 0 ]; then
      opts+=( "${@}" )
    fi

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:main:wp")
    opts=()

    if [ ! -z "${var_setup_local_uploads_zip_file:-}" ]; then
      opts+=( "--local_uploads_zip_file=${var_setup_local_uploads_zip_file:-}" )
    fi
    if [ ! -z "${var_setup_remote_uploads_zip_file:-}" ]; then
      opts+=( "--remote_uploads_zip_file=${var_setup_remote_uploads_zip_file:-}" )
    fi
    if [ ! -z "${var_setup_remote_bucket_path_uploads_dir:-}" ]; then
      opts+=( "--remote_bucket_path_uploads_dir=${var_setup_remote_bucket_path_uploads_dir:-}" )
    fi
    if [ ! -z "${var_setup_remote_bucket_path_uploads_file:-}" ]; then
      opts+=( "--remote_bucket_path_uploads_file=${var_setup_remote_bucket_path_uploads_file:-}" )
    fi
    if [ ! -z "${var_restore_service:-}" ]; then
      opts+=( "--restore_service=${var_restore_service:-}" )
    fi
    if [ ! -z "${var_uploads_service_dir:-}" ]; then
      opts+=( "--uploads_service_dir=${var_uploads_service_dir:-}" )
    fi
    if [ ! -z "${var_backup_bucket_name:-}" ]; then
      opts+=( "--backup_bucket_name=${var_backup_bucket_name:-}" )
    fi
    if [ ! -z "${var_backup_bucket_path:-}" ]; then
      opts+=( "--backup_bucket_path=${var_backup_bucket_path:-}" )
    fi
    if [ ! -z "${var_uploads_main_dir:-}" ]; then
      opts+=( "--uploads_main_dir=${var_uploads_main_dir:-}" )
    fi
    if [ ! -z "${var_backup_service:-}" ]; then
      opts+=( "--backup_service=${var_backup_service:-}" )
    fi
    if [ ! -z "${var_s3_endpoint:-}" ]; then
      opts+=( "--s3_endpoint=${var_s3_endpoint:-}" )
    fi
    if [ ! -z "${var_use_aws_s3:-}" ]; then
      opts+=( "--use_aws_s3=${var_use_aws_s3:-}" )
    fi
    if [ ! -z "${var_use_s3cmd:-}" ]; then
      opts+=( "--use_s3cmd=${var_use_s3cmd:-}" )
    fi
    if [ ! -z "${var_db_name:-}" ]; then
      opts+=( "--db_name=${var_db_name:-}" )
    fi
    if [ ! -z "${var_db_service:-}" ]; then
      opts+=( "--db_service=${var_db_service:-}" )
    fi
    if [ ! -z "${var_setup_local_db_file:-}" ]; then
      opts+=( "--local_db_file=${var_setup_local_db_file:-}" )
    fi
    if [ ! -z "${var_setup_remote_db_file:-}" ]; then
      opts+=( "--remote_db_file=${var_setup_remote_db_file:-}" )
    fi
    if [ ! -z "${var_setup_remote_bucket_path_db_dir:-}" ]; then
      opts+=( "--remote_bucket_path_db_dir=${var_setup_remote_bucket_path_db_dir:-}" )
    fi
    if [ ! -z "${var_setup_remote_bucket_path_db_file:-}" ]; then
      opts+=( "--remote_bucket_path_db_file=${var_setup_remote_bucket_path_db_file:-}" )
    fi
    if [ ! -z "${var_db_restore_dir:-}" ]; then
      opts+=( "--db_restore_dir=${var_db_restore_dir:-}" )
    fi
    if [ ! -z "${var_backup_delete_old_days:-}" ]; then
      opts+=( "--backup_delete_old_days=${var_backup_delete_old_days:-}" )
    fi
    if [ ! -z "${var_main_backup_base_dir:-}" ]; then
      opts+=( "--main_backup_base_dir=${var_main_backup_base_dir:-}" )
    fi
    if [ ! -z "${var_backup_bucket_uploads_sync_dir:-}" ]; then
      opts+=( "--backup_bucket_uploads_sync_dir=${var_backup_bucket_uploads_sync_dir:-}" )
    fi
    if [ ! -z "${var_backup_bucket_db_sync_dir:-}" ]; then
      opts+=( "--backup_bucket_db_sync_dir=${var_backup_bucket_db_sync_dir:-}" )
    fi

    if [ ! -z "${uploads_task_name:-}" ]; then
      opts+=( "--uploads_task_name=${uploads_task_name:-}" )
    fi
    if [ ! -z "${db_task_name:-}" ]; then
      opts+=( "--db_task_name=${db_task_name:-}" )
    fi    
    
    if [ ${#@} -ne 0 ]; then
      opts+=( "${@}" )
    fi

		"$pod_script_main_file" "$inner_cmd" "${opts[@]}"
		;;
  "args:db:wp")
    opts=()

    if [ ! -z "${var_db_name:-}" ]; then
      opts+=( "--db_name=${var_db_name:-}" )
    fi
    if [ ! -z "${var_db_service:-}" ]; then
      opts+=( "--db_service=${var_db_service:-}" )
    fi
    if [ ! -z "${var_db_user:-}" ]; then
      opts+=( "--db_user=${var_db_user:-}" )
    fi
    if [ ! -z "${var_db_pass:-}" ]; then
      opts+=( "--db_pass=${var_db_pass:-}" )
    fi
    if [ ! -z "${var_db_backup_dir:-}" ]; then
      opts+=( "--db_backup_dir=${var_db_backup_dir:-}" )
    fi
    if [ ! -z "${db_sql_file:-}" ]; then
      opts+=( "--db_sql_file=${db_sql_file:-}" )
    fi

		"$pod_script_db_file" "$inner_cmd" "${opts[@]}"
    ;;
  "setup:uploads:wp")
    "$pod_script_env_file" "args:main:wp" "${command%:*}" "$@"
    ;;
  "setup:uploads:wp"|"setup:uploads:verify:wp"|"setup:uploads:remote:wp")
    "$pod_script_main_file" "${command%:*}" "$@"
    ;;
  "setup:db:wp")
    "$pod_script_run_file" rm wordpress 
    "$pod_script_env_file" "args:main:wp" "${command%:*}" "$@"
    ;;
  "setup:db:remote:file:wp")
    "$pod_script_main_file" "${command%:*}" "$@"
    ;;
  "setup:db:verify:wp"|"setup:db:local:file:wp"|"backup:db:local:wp")
		"$pod_script_env_file" "args:db:wp" "${command%:*}:mysql" "$@"
		;;
  "setup:db:new:mysql")
    # Deploy a brand-new Wordpress site (with possibly seeded data)
    echo -e "${CYAN}$(date '+%F %X') - $command - installation${NC}"
    "$pod_script_run_file" run --rm wordpress \
      wp --allow-root core install \
      --url="$var_setup_url" \
      --title="$var_setup_title" \
      --admin_user="$var_setup_admin_user" \
      --admin_password="$var_setup_admin_password" \
      --admin_email="$var_setup_admin_email"

    if [ ! -z "$var_setup_local_seed_data" ] || [ ! -z "$var_setup_remote_seed_data" ]; then
      echo -e "${CYAN}$(date '+%F %X') - $command - deploy...${NC}"
      "$pod_script_env_file" deploy "$@"

      if [ ! -z "$var_setup_local_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import local seed data${NC}"
        "$pod_script_run_file" run --rm wordpress \
          wp --allow-root import ./"$var_setup_local_seed_data" --authors=create
      fi

      if [ ! -z "$var_setup_remote_seed_data" ]; then
        echo -e "${CYAN}$(date '+%F %X') - $command - import remote seed data${NC}"
        "$pod_script_run_file" run --rm wordpress sh -c \
          "curl -L -o ./tmp/tmp-seed-data.xml -k '$var_setup_remote_seed_data' \
          && wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
          && rm -f ./tmp/tmp-seed-data.xml"
      fi
    fi
    ;;
  "backup")
    "$pod_script_env_file" args "$command" "$@"
    ;;
	"migrate"|"update"|"fast-update"|"setup"|"fast-setup")
    "$pod_script_main_file" "$command" "$@"
    ;;
	"up"|"rm"|"exec-nontty"|"build"|"run"|"stop"|"exec"|"restart"|"logs"|"ps"|"sh"|"bash")
    "$pod_script_run_file" "$command" "$@"
		;;
  *)
		error "$command: invalid command"
    ;;
esac

end="$(date '+%F %X')"

case "$command" in
  "setup:db:new"|"deploy")
    echo -e "${CYAN}$(date '+%F %X') - env (shared) - $command - end${NC}"
    echo -e "${CYAN}env (shared) - $command - $start - $end${NC}"
    ;;
esac