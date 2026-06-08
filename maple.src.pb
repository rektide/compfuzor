---
- hosts: all
  vars:
    REPO: https://github.com/Makisuo/maple
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
