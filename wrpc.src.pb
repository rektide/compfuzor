---
- hosts: all
  vars:
    TYPE: wrpc
    INSTANCE: git
    REPO: https://github.com/bytecodealliance/wrpc
  tasks:
    - import_tasks: tasks/compfuzor.includes
