---
- hosts: all
  vars:
    REPO: https://github.com/containers/composefs-rs
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
