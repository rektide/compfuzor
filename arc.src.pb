---
- hosts: all
  vars:
    REPO: https://github.com/Basekick-Labs/arc
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
