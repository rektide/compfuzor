---
- hosts: all
  vars:
    REPO: https://github.com/ojowwalker77/Claude-Matrix
  tasks:
    - import_tasks: tasks/compfuzor.includes
