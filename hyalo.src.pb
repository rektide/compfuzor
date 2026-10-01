---
- hosts: all
  vars:
    REPO: https://github.com/ractive/hyalo
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
