---
- hosts: all
  vars:
    REPO: https://github.com/google/zx
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
