#!/bin/sh
debconf-get-selections | egrep "^\w*$1" | grep -v '^#' | 2json -s "program,key,type,value" -n -w 1,1,1,300 | json2yaml | yamlnest "${2:-base_selections}"
