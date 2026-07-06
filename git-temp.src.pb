---
- hosts: all
  vars:
    REPO: https://github.com/sebmellen/git-temp
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
