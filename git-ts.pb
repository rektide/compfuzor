---
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    TYPE: git-ts
    INSTANCE: git
    REPO: https://github.com/rektide/git-ts
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir=${DIR.stdout} npm install -g
