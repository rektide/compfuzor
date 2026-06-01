---
- hosts: all
  vars:
    REPO: https://github.com/starship/starship
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
