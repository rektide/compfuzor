---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/twitter/aurora
    TYPE: aurora
    INSTANCE: git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} make -C thrift install
  - shell: chdir={{DIR}} mvn -DskipTests
  - file: src={{DIR}} dest={{OPTS_DIR}}/{{NAME}} state=link
