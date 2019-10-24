#!/bin/sh

scripts_dir="{{ params.scripts_dir }}"
script_run_file="{{ params.script_run_file }}"
script_env_file="{{ params.script_env_file }}"
script_upgrade_file="{{ params.script_upgrade_file }}"

repo_name="{{ params.repo_name }}"
pod_env_dir="{{ params.pod_env_dir }}"
setup_url='{{ params.setup_url }}'
setup_title='{{ params.setup_title }}'
setup_admin_user='{{ params.setup_admin_user }}'
setup_admin_password='{{ params.setup_admin_password }}'
setup_admin_email='{{ params.setup_admin_email }}'
setup_local_db_file='{{ params.setup_local_db_file }}'
setup_local_uploads_zip_file='{{ params.setup_local_uploads_zip_file }}'
setup_remote_db_file='{{ params.setup_remote_db_file }}'
setup_remote_uploads_zip_file='{{ params.setup_remote_uploads_zip_file }}'
setup_remote_bucket_path_db_dir='{{ params.setup_remote_bucket_path_db_dir }}'
setup_remote_bucket_path_uploads_dir='{{ params.setup_remote_bucket_path_uploads_dir }}'
setup_remote_bucket_path_db_file='{{ params.setup_remote_bucket_path_db_file }}'
setup_remote_bucket_path_uploads_file='{{ params.setup_remote_bucket_path_uploads_file }}'
setup_local_seed_data='{{ params.setup_local_seed_data }}'
setup_remote_seed_data='{{ params.setup_remote_seed_data }}'
s3_endpoint='{{ params.s3_endpoint }}'
use_aws_s3='{{ params.use_aws_s3 }}'
use_s3cmd='{{ params.use_s3cmd }}'
backup_bucket_name='{{ params.backup_bucket_name }}'
backup_bucket_path='{{ params.backup_bucket_path }}'
backup_bucket_db_sync_dir='{{ params.backup_bucket_db_sync_dir }}'
backup_bucket_uploads_sync_dir='{{ params.backup_bucket_uploads_sync_dir }}'
backup_delete_old_days='{{ params.backup_delete_old_days }}'
db_user='{{ params.db_user }}'
db_pass='{{ params.db_pass }}'
db_name='{{ params.db_name }}'

wordpress_dev_repo_dir="{{ params.wordpress_dev_repo_dir | default('') }}"
