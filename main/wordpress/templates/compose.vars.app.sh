#!/bin/sh

scripts_dir={{ params.scripts_dir | quote }}
script_run_file={{ params.script_run_file | quote }}
script_env_file={{ params.script_env_file | quote }}
script_upgrade_file={{ params.script_upgrade_file | quote }}

repo_name={{ params.repo_name | quote }}
pod_env_dir={{ params.pod_env_dir | quote }}
setup_url={{ params.setup_url | quote }}
setup_title={{ params.setup_title | quote }}
setup_admin_user={{ params.setup_admin_user | quote }}
setup_admin_password={{ params.setup_admin_password | quote }}
setup_admin_email={{ params.setup_admin_email | quote }}
setup_local_db_file={{ params.setup_local_db_file | quote }}
setup_local_uploads_zip_file={{ params.setup_local_uploads_zip_file | quote }}
setup_remote_db_file={{ params.setup_remote_db_file | quote }}
setup_remote_uploads_zip_file={{ params.setup_remote_uploads_zip_file | quote }}
setup_remote_bucket_path_db_dir={{ params.setup_remote_bucket_path_db_dir | quote }}
setup_remote_bucket_path_uploads_dir={{ params.setup_remote_bucket_path_uploads_dir | quote }}
setup_remote_bucket_path_db_file={{ params.setup_remote_bucket_path_db_file | quote }}
setup_remote_bucket_path_uploads_file={{ params.setup_remote_bucket_path_uploads_file | quote }}
setup_local_seed_data={{ params.setup_local_seed_data | quote }}
setup_remote_seed_data={{ params.setup_remote_seed_data | quote }}
s3_endpoint={{ params.s3_endpoint | quote }}
use_aws_s3={{ params.use_aws_s3 | lower | quote }}
use_s3cmd={{ params.use_s3cmd | lower | quote }}
backup_bucket_name={{ params.backup_bucket_name | quote }}
backup_bucket_path={{ params.backup_bucket_path | quote }}
backup_bucket_db_sync_dir={{ params.backup_bucket_db_sync_dir | quote }}
backup_bucket_uploads_sync_dir={{ params.backup_bucket_uploads_sync_dir | quote }}
backup_delete_old_days={{ params.backup_delete_old_days | quote }}
db_user={{ params.db_user | quote }}
db_pass={{ params.db_pass | quote }}
db_name={{ params.db_name | quote }}

old_domain_host={{ params.old_domain_host | quote }}
new_domain_host={{ params.new_domain_host | quote }}

wordpress_dev_repo_dir={{ params.wordpress_dev_repo_dir | default('') | quote }}
