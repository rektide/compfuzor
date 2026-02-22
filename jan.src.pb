---
- hosts: all
  vars:
    # also https://app.jan.ai/download/latest/linux-amd64-deb
    REPO: https://github.com/janhq/jan
  tasks:
    - import_tasks: tasks/compfuzor.includes
