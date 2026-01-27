---
- hosts: all
  vars:
    REPO: https://tangled.org/oppi.li/pdsfs
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
