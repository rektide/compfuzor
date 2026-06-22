---
- hosts: all
  vars:
    REPO: https://github.com/wild-linker/wild
    RUST: True
    RUST_PKG: wild-linker
  tasks:
    - import_tasks: tasks/compfuzor.includes
