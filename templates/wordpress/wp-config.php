<?php

// Added by W3 Total Cache
{{ tpl.wp.w3_tc_edge_mode | default(false) | ternary('', '//') 
}}define('W3TC_EDGE_MODE', {{ tpl.wp.w3_tc_edge_mode | default("") }});
{{ tpl.wp.wp_cache | default(false) | ternary('', '//') 
}}define('WP_CACHE', {{ tpl.wp.wp_cache | default("") }}); 

define('DB_HOST', getenv('DB_HOST'));
define('DB_NAME', getenv('DB_NAME'));
define('DB_USER', getenv('DB_USER'));
define('DB_PASSWORD', '{{ tpl.main.db_password }}');
define('DB_CHARSET', '{{ tpl.wp.db_charset | default("utf8mb4") }}');
define('DB_COLLATE', '{{ tpl.wp.db_collate | default("") }}');

define('WP_HOME', '{{ tpl.main.protocol }}://{{ tpl.main.domain }}');
define('WP_SITEURL', '{{ tpl.main.protocol }}://{{ tpl.main.domain }}');

// Generate keys automatically at:
// https://api.wordpress.org/secret-key/1.1/salt/
define('AUTH_KEY',         '{{ tpl.wp.auth_key }}');
define('SECURE_AUTH_KEY',  '{{ tpl.wp.secure_auth_key }}');
define('LOGGED_IN_KEY',    '{{ tpl.wp.logged_in_key }}');
define('NONCE_KEY',        '{{ tpl.wp.nonce_key }}');
define('AUTH_SALT',        '{{ tpl.wp.auth_salt }}');
define('SECURE_AUTH_SALT', '{{ tpl.wp.secure_auth_salt }}');
define('LOGGED_IN_SALT',   '{{ tpl.wp.logged_in_salt }}');
define('NONCE_SALT',       '{{ tpl.wp.nonce_salt }}');

$table_prefix  = '{{ tpl.wp.table_prefix | default("wp_") }}';

define('WPLANG', '{{ tpl.wp.wplang | default("en_US") }}');
define('WP_DEBUG', {{ tpl.wp.wp_debug | default(false) | lower }});

define('DO_NOT_UPGRADE_GLOBAL_TABLES', {{ tpl.wp.do_not_upgrade_global_tables | default(true) | lower }});
define('DISALLOW_FILE_EDIT', {{ tpl.wp.disallow_file_edit | default(true) | lower }});
define('DISALLOW_FILE_MODS', {{ tpl.wp.disallow_file_mods | default(true) | lower }});

if ( !defined('ABSPATH') )
	define('ABSPATH', dirname(__FILE__) . '/');

require_once(ABSPATH . 'wp-settings.php');
