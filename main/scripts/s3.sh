#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_tmp_dir="$POD_TMP_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

RED='\033[0;31m'
NC='\033[0m' # No Color

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (db)."
fi

shift;

while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"       # extract long option name
		OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		s3_service ) arg_s3_service="${OPTARG:-}";;
		s3_endpoint ) arg_s3_endpoint="${OPTARG:-}";;
		s3_bucket_name ) arg_s3_bucket_name="${OPTARG:-}";;
		s3_src ) arg_s3_src="${OPTARG:-}" ;;
		s3_dest ) arg_s3_dest="${OPTARG:-}";;
		s3_opts ) arg_s3_opts=( "${@:OPTIND}" ); break;; 
		??* ) error "Illegal option --$OPT" ;;  # bad long option
		\? )  exit 2 ;;  # bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

function awscli_general {
	>&2 echo ">$1 $arg_s3_service: aws ${*:2}"
	>&2 "$pod_script_env_file" "$1" "$arg_s3_service" aws "${@:2}"
}

function awscli_exec {
	awscli_general exec-nontty "${@}"
}

function awscli_run {
	awscli_general run "${@}"
}

function awscli_is_empty_bucket {
	cmd="$1"

	error_log_dir="$pod_tmp_dir/s3/"
	mkdir -p "$error_log_dir"

	error_filename="error.$(date '+%s').$(od -A n -t d -N 1 /dev/urandom | grep -o "[0-9]*").log"
	error_log_file="$error_log_dir/$error_filename"	

	if ! awscli_general "$cmd" \
		s3 --endpoint="$arg_s3_endpoint" \
		ls "s3://$arg_s3_bucket_name" \
		2> "$error_log_file"; 
	then
		if grep -q 'NoSuchBucket' "$error_log_file"; then
			echo "true"
			exit 0
		fi
	fi
		
	echo "false"
}

function awscli_rb {
	cmd="$1"

	empty_bucket="$(awscli_is_empty_bucket "$cmd")"

	if [ "$empty_bucket" = "true" ]; then
		>&2 echo "skipping (no_bucket)"
	elif [ "$empty_bucket" = "false" ]; then
		awscli_general "$cmd" s3 rb --endpoint="$arg_s3_endpoint" --force "s3://$arg_s3_bucket_name" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
	else
		error "$command - awscli_rb: invalid result (empty_bucket should be true or false): $empty_bucket"
	fi
}

function s3cmd_general {
	>&2 "$pod_script_env_file" "$1" "$arg_s3_service" s3cmd "${@:2}"
}

function s3cmd_exec {
	s3cmd_general exec-nontty "${@}"
}

function s3cmd_run {
	s3cmd_general run "${@}"
}

case "$command" in
	"s3:awscli:exec:is_empty_bucket")
		awscli_is_empty_bucket exec-nontty
	  ;;
	"s3:awscli:run:is_empty_bucket")
		awscli_is_empty_bucket run
	  ;;
  "s3:awscli:exec:create-bucket")
		awscli_exec s3api create-bucket --endpoint="$arg_s3_endpoint" --bucket "$arg_s3_bucket_name" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:awscli:run:create-bucket")
		awscli_run s3api create-bucket --endpoint="$arg_s3_endpoint" --bucket "$arg_s3_bucket_name" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:awscli:exec:rb")
		awscli_rb exec-nontty
		;;
  "s3:awscli:run:rb")
		awscli_rb run
		;;
	"s3:awscli:exec:cp")
		awscli_exec s3 cp --endpoint="$arg_s3_endpoint" "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:awscli:run:cp")
		awscli_run s3 cp --endpoint="$arg_s3_endpoint" "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:awscli:exec:sync")
		awscli_exec s3 sync --endpoint="$arg_s3_endpoint" "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:awscli:run:sync")
		awscli_run s3 sync --endpoint="$arg_s3_endpoint" "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:s3cmd:exec:cp")
		s3cmd_exec cp "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:s3cmd:run:cp")
		s3cmd_run cp "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
		;;
  "s3:s3cmd::exec:sync")
		s3cmd_exec sync "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
    ;;
  "s3:s3cmd::run:sync")
		s3cmd_run sync "$arg_s3_src" "$arg_s3_dest" ${arg_s3_opts[@]+"${arg_s3_opts[@]}"}
    ;;
  *)
		error "Invalid command: $command"
    ;;
esac