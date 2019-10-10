{% if params.login_cookie_validity is defined %}
$cfg['LoginCookieValidity'] = {{ params.login_cookie_validity }};
{% endif %}  