---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/TryGhost/Ghost
    TYPE: ghost
    INSTANCE: git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
