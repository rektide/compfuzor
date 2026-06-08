---
- hosts: all
  vars:
    REPO: https://github.com/panproto/panproto
    RUST: True
    RUST_PKG: panproto-cli
    RUST_BIN: schema
  tasks:
    - import_tasks: tasks/compfuzor.includes
