---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/apache/thrift
    TYPE: thrift
    INSTANCE: git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} ./bootstrap.sh
  - shell: chdir={{DIR}} ./configure --prefix={{OPTS_DIR}}/{{NAME}}
  - shell: chdir={{DIR}} make
  - shell: chdir={{DIR}} make install
    sudo: yes
  - file: src={{OPTS_DIR}}/bin/thrift dest=/usr/local/src/bin state=link
