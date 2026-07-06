---
- hosts: all
  vars:
    REPO: https://github.com/railwayapp/railpack
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
