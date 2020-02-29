# 1. Remote Restore

## 1.1. Restore File

### 1.1.1. Restore File from Remote Bucket Directory

`restore_remote_bucket_path_dir`: this parameter is required and corresponds to the s3 remote directory that will be synchronized with the local directory (in the path `s3_bucket_name`/`s3_bucket_path`).

`restore_dest_dir`: this parameter is required and corresponds to the local directory that will receive the restored files and folders present in the remote bucket.

`restore_dest_file`: optional parameter that, when specified, will make that only this file in the remote bucket directory will be synchronized.

### 1.1.2. Restore File from Local, Remote, or Remote Bucket File

`restore_local_file`: local file to be restored (must already be present in the machine storage).

`restore_remote_file`: remote file to be restored (via `curl`).

`restore_remote_bucket_path_file`: remote file in a bucket to be restored (in the path `s3_bucket_name`/`s3_bucket_path`).

`restore_dest_file`: required parameter, it will be the final file generated in the restore process.

**Can be used with:**

`restore_is_zip_file`: `true` if the restored file is a zip file that needs to be unzipped.

`restore_zip_pass`: password of the zip file (empty if there isn't a password).

`restore_zip_inner_dir`: directory to be extracted from the zip file (if it's restoring a directory).

`restore_zip_inner_file`: file to be extracted from the zip file (if it's restoring a file).

_If it's restoring a directory, `restore_is_zip_file` must be `true` and `restore_zip_inner_dir` must be defined, otherwise an error is thrown._

_If it's restoring a file, `restore_is_zip_file` is `true` and `restore_zip_inner_file` is not defined, an error is thrown._
