---
- hosts: all
  vars:
    REPO: https://github.com/kenn-io/kata
    GO: True
    GO_BIN: kata
    GO_TARGET: ./cmd/kata
  tasks:
    - import_tasks: tasks/compfuzor.includes
