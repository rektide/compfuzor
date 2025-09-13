---
- hosts: all
  vars:
    TYPE: yals
    INSTANCE: git
    REPO: https://github.com/theroyallab/YALS
  tasks:
    - import_tasks: tasks/compfuzor.includes
