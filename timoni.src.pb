---
- hosts: all
  vars:
    REPO: https://github.com/stefanprodan/timoni
    GO: True
    GO_BIN: timoni
    GO_TARGET: ./cmd/timoni
  tasks:
    - import_tasks: tasks/compfuzor.includes
