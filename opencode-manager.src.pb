---
- hosts: all
  vars:
    REPO: https://github.com/chriswritescode-dev/opencode-manager
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
