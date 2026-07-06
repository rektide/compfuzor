---
- hosts: all
  vars:
    REPO: https://github.com/railwayapp/cli
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
