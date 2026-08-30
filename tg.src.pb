---
- hosts: all
  vars:
    REPO: https://tangled.org/aly.codes/tg
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
