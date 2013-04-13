---
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    TYPE: llvm
    INSTANCE: git
    REPO: http://llvm.org/git/llvm.git
    clang_repo: http://llvm.org/git/clang.git
    clang_dir: ${SRCS_DIR}/clang-${INSTANCE}
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: echo hello
  - git: repo=${clang_repo} dest=${clang_dir}
