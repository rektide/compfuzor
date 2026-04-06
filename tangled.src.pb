---
- hosts: all
  vars:
    TYPE: tangled-cli
    INSTANCE: main
    REPO: https://tangled.org/markbennett.ca/tangled-cli
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
