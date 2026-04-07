---
- hosts: all
  vars:
    REPO: https://tangled.org/mary.md.id/atcute
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
