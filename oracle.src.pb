---
- hosts: all
  vars:
    REPO: https://github.com/steipete/oracle
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
