---
- hosts: all
  vars:
    REPO: https://tangled.org/solpbc.org/rookery
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
