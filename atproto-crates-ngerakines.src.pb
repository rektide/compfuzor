---
- hosts: all
  vars:
    REPO: https://tangled.org/ngerakines.me/atproto-crates
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
