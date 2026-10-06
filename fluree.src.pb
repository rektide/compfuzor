---
- hosts: all
  vars:
    REPO: https://github.com/fluree/db
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
