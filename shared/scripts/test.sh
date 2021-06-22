#!/bin/bash
set -eou pipefail

inner_run_file="/var/main/scripts/run"
# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO"; exit $LINENO;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env - shared)."
fi

shift;

case "$command" in
	"shared:test:tmp")
		dest_file="$("$pod_script_env_file" "run:util:replace_placeholders" \
			--task_info="test" \
			--task_name="mytest" \
			--subtask_cmd="$command" \
			--toolbox_service="toolbox" \
			--value="my-file.[[date]]..[[time]].txt")" \
			|| error "$command: replace_placeholders (dest_file)"

		echo "dest_file=$dest_file"
		;;
	"inner:shared:test:tmp")
		dest_file="$("$pod_script_env_file" "inner:util:replace_placeholders" \
			--task_info="test" \
			--value="my-file-inner.[[date]]..[[time]].txt")" \
			|| error "$command: replace_placeholders (dest_file)"

		echo "dest_file=$dest_file"
		;;
	"inner:shared:test")
		echo "test inside a container - args: ${*}" >&2
		;;
	"shared:test:s3:delete_old")
		if [ "${var_main__local:-}" = 'true' ]; then
			"$pod_script_env_file" "s3:subtask:s3_backup" \
				--s3_cmd='delete_old' \
				--s3_path="log" \
				--s3_older_than_days="3" \
				--s3_test='true'
		fi
		;;
	"shared:test:zip")
		"$pod_script_env_file" up toolbox

		"$pod_script_env_file" exec-nontty toolbox \
			"$inner_run_file" "inner:shared:test:zip"
		;;
	"inner:shared:test:zip")
		rm -rf /tmp/main/test/src/
		rm -rf /tmp/main/test/dest/
		mkdir -p /tmp/main/test/src/dir/
		mkdir -p /tmp/main/test/dest

		echo "\$(date '+%F %X') - test 1 ($$)" > /tmp/main/test/src/file1.txt
		echo "\$(date '+%F %X') - test 2 ($$)" > /tmp/main/test/src/dir/file2.txt
		echo "\$(date '+%F %X') - test 3 ($$)" > /tmp/main/test/src/dir/file3.txt
		echo "\$(date '+%F %X') - test 4 ($$)" > /tmp/main/test/src/dir/file4.txt

		mkdir -p /tmp/main/test/dest/

		"$pod_script_env_file" "inner:compress:zip" \
			--task_info="test-1.1 - $command" \
			--toolbox_service="toolbox" \
			--task_kind="file" \
			--src_file="/tmp/main/test/src/file1.txt" \
			--dest_file="/tmp/main/test/dest/file.zip"

		"$pod_script_env_file" "inner:compress:zip" \
			--task_info="test-1.2 - $command" \
			--toolbox_service="toolbox" \
			--task_kind="dir" \
			--src_dir="/tmp/main/test/src/dir" \
			--dest_file="/tmp/main/test/dest/dir.zip"

		"$pod_script_env_file" "inner:compress:zip" \
			--task_info="test-1.3 - $command" \
			--toolbox_service="toolbox" \
			--task_kind="dir" \
			--src_dir="/tmp/main/test/src/dir" \
			--dest_file="/tmp/main/test/dest/flat.zip" \
			--flat="true"

		"$pod_script_env_file" "inner:compress:zip" \
			--task_info="test-1.4 - $command" \
			--toolbox_service="toolbox" \
			--task_kind="file" \
			--src_file="/tmp/main/test/src/dir/file2.txt" \
			--dest_file="/tmp/main/test/dest/pass.zip" \
			--compress_pass="123456"
		;;
	"shared:test:unzip")
		"$pod_script_env_file" up toolbox

		"$pod_script_env_file" exec-nontty toolbox \
			"$inner_run_file" "inner:shared:test:unzip"
		;;
	"inner:shared:test:unzip")
		rm -rf /tmp/main/test/newdest/

		mkdir -p /tmp/main/test/newdest/file
		mkdir -p /tmp/main/test/newdest/dir
		mkdir -p /tmp/main/test/newdest/flat
		mkdir -p /tmp/main/test/newdest/pass

		"$pod_script_env_file" "inner:uncompress:zip" \
			--task_info="test-2.1 - $command" \
			--toolbox_service="toolbox" \
			--src_file="/tmp/main/test/dest/file.zip" \
			--dest_dir="/tmp/main/test/newdest/file" \
			--compress_pass=""

		"$pod_script_env_file" "inner:uncompress:zip" \
			--task_info="test-2.2 - $command" \
			--toolbox_service="toolbox" \
			--src_file="/tmp/main/test/dest/dir.zip" \
			--dest_dir="/tmp/main/test/newdest/dir" \
			--compress_pass=""

		"$pod_script_env_file" "inner:uncompress:zip" \
			--task_info="test-2.3 - $command" \
			--toolbox_service="toolbox" \
			--src_file="/tmp/main/test/dest/flat.zip" \
			--dest_dir="/tmp/main/test/newdest/flat" \
			--compress_pass=""

		"$pod_script_env_file" "inner:uncompress:zip" \
			--task_info="test-2.4 - $command" \
			--toolbox_service="toolbox" \
			--src_file="/tmp/main/test/dest/pass.zip" \
			--dest_dir="/tmp/main/test/newdest/pass" \
			--compress_pass="123456"
		;;
	"inner:shared:test:container:image:tag:exists"|"shared:test:container:image:tag:exists")
    	registry_api_base_url="https://hub.docker.com/v2"
    	repository="lucasbasquerotto/image"
		version="toolbox-20200715-023"
		username=''
		userpass=''

		base_cmd='run'
		[[ $command == "inner:"* ]] && base_cmd='inner'

		[[ $command != "inner:"* ]] && "$pod_script_env_file" up "toolbox"

		"$pod_script_env_file" "$base_cmd:container:image:tag:exists" \
			--task_info="test - $command" \
			--toolbox_service="toolbox" \
			--registry_api_base_url="$registry_api_base_url" \
			--repository="$repository" \
			--version="$version" \
			--username="$username" \
			--userpass="$userpass"
		;;
	*)
		error "$command: invalid command"
		;;
esac
