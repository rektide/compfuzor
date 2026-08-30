---
- hosts: all
  vars:
    REPO: https://github.com/herdrdev/herdr
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
