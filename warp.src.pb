---
- hosts: all
  vars:
    REPO: https://github.com/warpdotdev/warp
  tasks:
    - import_tasks: tasks/compfuzor.includes
