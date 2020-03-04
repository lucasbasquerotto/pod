# 1. Remote Script

# 1.1. Restore

`task_kind`: `dir` if it's restoring a directory (or a zipped file that will be generate a directory) or `file` if it's restoring a file.

`toolbox_service`: container service containing utilities like `bash`, `cp`, `mv`, `curl`, `zip` and `unzip`. The container must be running (will be run with `exec`).

`s3_task_name`: name of the task to execute `s3` commands (the task must be defined called from a more specific script file).

`s3_bucket_name`: name of the bucket to be used in the restore process (if it's restoring from a bucket directory or file).

`s3_bucket_path`: path in the bucket to be used in the restore process (if it's restoring from a bucket directory or file). An empty path implies the root of the bucket.

## 1.1.1. Restore File from Remote Bucket Directory

`restore_remote_bucket_path_dir`: this parameter is required and corresponds to the s3 remote directory that will be synchronized with the local directory (in the path `s3_bucket_name`/`s3_bucket_path`).

`restore_dest_dir`: this parameter is required and corresponds to the local directory that will receive the restored files and folders present in the remote bucket.

`restore_dest_file`: optional parameter that, when specified, will make that only this file in the remote bucket directory will be synchronized.

## 1.1.2. Restore File from Local, Remote, or Remote Bucket File

`restore_dest_dir`: required, it will be the final directory (if it's restoring a directory) or the directory containing the final file (if it's restoring a file) generated in the restore process.

`restore_dest_file`: it will be the final file generated in the restore process (inside `restore_dest_dir`). _If it's restoring a file, it must be defined, otherwise an error is thrown._

`restore_tmp_dir`: required, temporary directory where the restored file (or the intermediate zip file containing the file or directory to be restored) will be stored temporarily.

**One of the following must be specified:**

`restore_local_file`: local file to be restored (must already be present in the machine storage).

`restore_remote_file`: remote file to be restored (via `curl`).

`restore_remote_bucket_path_file`: remote file in a bucket to be restored (in the path `s3_bucket_name`/`s3_bucket_path`).

**Can be used with:**

`restore_is_zip_file`: `true` if the restored file is a zip file that needs to be unzipped.

`restore_zip_tmp_file_name`: name of the temporary zip file restored (will be inside `restore_tmp_dir`). Required if `restore_is_zip_file` is `true`.

`restore_zip_pass`: password of the zip file (empty if there isn't a password).

`restore_zip_inner_dir`: directory to be extracted from the zip file (if it's restoring a directory).

`restore_zip_inner_file`: file to be extracted from the zip file (if it's restoring a file).

_If it's restoring a directory, `restore_is_zip_file` must be `true` and `restore_zip_inner_dir` must be defined, otherwise an error is thrown._

_If it's restoring a file, `restore_is_zip_file` is `true` and `restore_zip_inner_file` is not defined, an error is thrown._

# 1.2. Backup

`task_kind`: `dir` if it's making the backup of a directory (or a zipped file that will be generate a directory) or `file` if it's restoring a file.

`toolbox_service`: container service containing utilities like `bash`, `cp`, `mv`, `curl`, `zip` and `unzip`. The container must be running (will be run with `exec`).

`s3_task_name`: name of the task to execute `s3` commands (the task must be defined called from a more specific script file).

`s3_bucket_name`: name of the bucket to be used in the restore process (if it's restoring from a bucket directory or file).

`s3_bucket_path`: path in the bucket to be used in the restore process (if it's restoring from a bucket directory or file). An empty path implies the root of the bucket.

