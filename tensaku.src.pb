---
- hosts: all
  vars:
    REPO: https://github.com/jondkinney/tensaku
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
