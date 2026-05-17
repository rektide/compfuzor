---
- hosts: all
  vars:
    REPO: https://github.com/tmuxpack/tpack
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
