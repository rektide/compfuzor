---
- hosts: all
  gather_facts: false
  vars:
    TYPE: grunt
    INSTANCE: git
    repo_base: https://github.com/gruntjs
    repos:
    - grunt-init
    - grunt-cli
    DIR_BYPASS: true
  vars_files:
  - vars/common.vars
  - vars/src.vars
  gather_facts: false
  tasks:
  - include: tasks/cfvar_includes.tasks
  - git: repo=$repo_base/$item dest=$SRCS_DIR/$item-$INSTANCE
    with_items: $repos
  - include: tasks/npm.installg.tasks dir=$SRCS_DIR/$item-$INSTANCE
    with_items: $repos
