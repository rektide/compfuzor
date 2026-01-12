---
- hosts: all
  vars:
    REPO: https://github.com/idursun/jjui
    GO: True
    GO_TARGET: ./cmd/jjui
  tasks:
    - import_tasks: tasks/compfuzor.includes
