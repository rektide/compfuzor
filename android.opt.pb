---
- hosts: all
  gather_facts: False
  vars:
    TYPE: repo
    INSTANCE: git
    REPO: https://android.googlesource.com/tools/repo
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - file: src={{SRCS_DIR}}/repo dest={{BINS_DIR}}/repo state=link
