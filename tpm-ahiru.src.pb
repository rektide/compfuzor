---
- hosts: all
  vars:
    REPO: https://codeberg.org/x3ro/ahiru-tpm
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
