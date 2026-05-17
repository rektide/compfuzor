---
- hosts: all
  vars:
    REPO: https://github.com/tmuxpack/tpack
    GO: True
    GO_BIN: tpack
    GO_TARGET: ./cmd/tpack
  tasks:
    - import_tasks: tasks/compfuzor.includes
