---
- hosts: all
  vars:
    REPO: https://github.com/dagger/dagger
    GO: True
    GO_BIN: dagger
    GO_TARGET: ./cmd/dagger
  tasks:
    - import_tasks: tasks/compfuzor.includes
