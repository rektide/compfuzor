---
- hosts: all
  vars:
    TYPE: jco
    INSTANCE: git
    REPO: https://github.com/bytecodealliance/jco
  tasks:
    - import_tasks: tasks/compfuzor.includes
