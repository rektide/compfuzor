---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/apache/mesos
    TYPE: mesos
    INSTANCE: git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} ./bootstrap
  - shell: chdir={{DIR}} ./configure --prefix={{OPTS_DIR}}/{{NAME}}
  - shell: chdir={{DIR}} make
  - shell: chdir={{DIR}} make install
    sudo: yes
