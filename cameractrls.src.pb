---
- hosts: all
  vars:
    REPO: https://github.com/soyersoyer/cameractrls
  tasks:
    - import_tasks: tasks/compfuzor.includes
