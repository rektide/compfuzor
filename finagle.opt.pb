---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/twitter/finagle
    TYPE: finagle
    INSTANCE: git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} ./sbt test
  - file: src={{DIR}} dest={{OPTS_DIR}}/{{NAME}} state=link
