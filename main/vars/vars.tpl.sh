#!/bin/sh

{% for item in params | default({}) | dict2items | sort(attribute='key') | list 
%}{{ item.key }}={{ item.value | quote }}
{% endfor %}
