#!/bin/sh
debconf-get-selection | egrep '^\w*$1' | grep -v '^#' | 2json -s "program,key,type,value" -n -o "${2:-base_selections}" | json2yaml
