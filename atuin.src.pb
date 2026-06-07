---
- hosts: all
  vars:
    REPO: https://github.com/atuinsh/atuin
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
