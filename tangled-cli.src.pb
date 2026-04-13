---
- hosts: all
  vars:
    REPO: https://tangled.org/markbennett.ca/tangled-cli
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
