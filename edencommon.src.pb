---
- hosts: all
  vars:
    REPO: https://github.com/facebookexperimental/edencommon
    CMAKE: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
