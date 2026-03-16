---
- hosts: all
  vars:
    TYPE: https://github.com/crossplane/crossplane
  tasks:
    - import_tasks: tasks/compfuzor.includes
