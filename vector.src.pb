---
- hosts: all
  vars:
    REPO: https://github.com/vectordotdev/vector
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
