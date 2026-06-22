---
- hosts: all
  vars:
    REPO: https://github.com/bluesky-social/goat
    GO: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
