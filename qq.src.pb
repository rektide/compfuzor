---
- hosts: all
  vars:
    REPO: https://github.com/JFryy/qq
    GO: True
    GO_BIN: bin/qq
    GO_TARGET: './'
  tasks:
    - import_tasks: tasks/compfuzor.includes
