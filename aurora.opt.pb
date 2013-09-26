---
- hosts: all
  gather_facts: False
  vars:
    REPO: https://github.com/twitter/aurora
    TYPE: aurora
    INSTANCE: git
    idls:
    - api.thrift
    - storage.thrift
    - storage_local.thrift
    idl_dir: "thrift/src/main/thrift/com/twitter/aurora/gen"
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  #- shell: chdir={{DIR}} make -C thrift install
  #- shell: chdir={{DIR}} mvn -DskipTests
  - file: src={{DIR}} dest={{OPTS_DIR}}/{{NAME}} state=link
  - file: path={{SRCS_DIR}}/idl/{{NAME}} state=directory
  - file: src={{DIR}}/{{idl_dir}}/{{item}} dest={{SRCS_DIR}}/idl/{{NAME}}/{{item}} state=link
    with_items: idls
