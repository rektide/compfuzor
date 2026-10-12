---
- hosts: all
  vars:
    REPO: https://github.com/holos-run/holos
    GO: True
    GO_BIN: holos
    GO_TARGET: ./cmd/holos
  tasks:
    - import_tasks: tasks/compfuzor.includes
