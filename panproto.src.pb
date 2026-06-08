---
- hosts: all
  vars:
    REPO: https://github.com/panproto/panproto
    RUST: True
    RUST_ALL: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
