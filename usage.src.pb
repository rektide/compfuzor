---
- hosts: all
  vars:
    REPO: https://github.com/jdx/usage
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
