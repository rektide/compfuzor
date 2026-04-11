---
- hosts: all
  vars:
    REPO: https://github.com/solpbc/vit
  tasks:
    - import_tasks: tasks/compfuzor.includes
