#!/bin/sh
# shellcheck disable=SC2034,SC2209

{% for item in params | default({}) | dict2items | sort(attribute='key') | rejectattr('value', 'equalto', '') | list
%}{{ item.key }}={{ item.value | quote }}
{% endfor %}
