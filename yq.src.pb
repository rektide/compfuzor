---
- hosts: all
  vars:
    REPO: https://github.com/mikefarah/yq
    GO: True
    GO_BIN: yq.go
  tasks:
    - import_tasks: tasks/compfuzor.includes
