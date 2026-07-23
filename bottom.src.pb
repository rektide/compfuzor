---
- hosts: all
  vars:
    REPO: https://github.com/ClementTsang/bottom
    RUST: True
    RUST_BIN: btm
  tasks:
    - import_tasks: tasks/compfuzor.includes
