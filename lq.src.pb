---
- hosts: all
  vars:
    REPO: https://github.com/clux/lq
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
