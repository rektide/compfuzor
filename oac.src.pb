---
- hosts: all
  vars:
    REPO: https://github.com/AOMediaCodec/oac
  tasks:
    - import_tasks: tasks/compfuzor.includes
