---
- hosts: all
  vars:
    REPO: https://github.com/j4ckxyz/skycoll
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
