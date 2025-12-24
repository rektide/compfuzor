---
- hosts: all
  vars:
    REPO: https://github.com/henryhawke/ReasonSuite
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
