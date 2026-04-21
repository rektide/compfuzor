---
- hosts: all
  vars:
    REPO: https://github.com/checkpoint-restore/checkpointctl
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
