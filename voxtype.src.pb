---
- hosts: all
  vars:
    REPO: https://github.com/peteonrails/voxtype
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
