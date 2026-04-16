---
- hosts: all
  vars:
    REPO: https://github.com/j4ckxyz/skycoll
    PYTHON: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
