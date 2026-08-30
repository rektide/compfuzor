---
- hosts: all
  vars:
    REPO: https://tangled.org/permadeath.com/atgc
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
