#!/bin/sh

{% for item in params | default({}) | dict2items | list 
%}{{ item.key }}={{ item.value | quote }}
{% endfor %}
