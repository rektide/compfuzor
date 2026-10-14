---
- hosts: all
  vars:
    REPO: https://github.com/EzraCerpac/jj-waltz
    RUST: True
    RUST_BIN: jw
  tasks:
    - import_tasks: tasks/compfuzor.includes
