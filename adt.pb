---
- hosts: all
  vars:
    TYPE: adt
    INSTANCE: kitkat
    file: adt-bundle-linux-x86_64-20131030.zip
    url: "http://dl.google.com/android/adt/{{file}}"
  vars_files:
  - vars/common.vars
  - vars/opt.vars
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - get_url: url="{{url}}" dest="{{SRCS_DIR}}/{{file}}"
  - shell: chdir="{{OPTS_DIR}}" unzip "{{SRCS_DIR}}/{{file}}"
  - file: path="{{OPT_DIR}}" state=absent
  - shell: chdir="{{OPTS_DIR}}" mv adt-bundle-linux-x86_64-20131030 "{{NAME}}"
