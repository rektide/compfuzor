---
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    TYPE: openwrt
    REPO: https://github.com/mirrors/openwrt.git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - git: repo=${REPO} dest=${DIR.stdout}

