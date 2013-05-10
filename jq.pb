---
- hosts: all
  gather_facts: false
  vars:
    TYPE: jq
    INSTANCE: git
    REPO: https://github.com/stedolan/jq.git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} make
  - shell: chdir={{DIR}} make install
