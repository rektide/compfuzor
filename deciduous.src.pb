
---
- hosts: all
  vars:
    REPO: https://github.com/notactuallytreyanastasio/deciduous
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
