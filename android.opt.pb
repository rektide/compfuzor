---
- hosts: all
  gather_facts: False
  vars:
    TYPE: android
    INSTANCE: git
    repo_url: https://dl-ssl.google.com/dl/googlesource/git-repo/repo
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{SRCS_DIR}} uget {{repo_url}}
  - file: path={{SRCS_DIR}}/repo mode=555
  - file: src={{SRCS_DIR}}/repo dest={{BINS_DIR}}/repo state=link
