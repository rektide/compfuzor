---
- hosts: all
  vars:
    TYPE: https://github.com/atrium-rs/atrium
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
