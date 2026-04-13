---
- hosts: all
  vars:
    REPO: https://github.com/solpbc/vit
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
