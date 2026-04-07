---
- hosts: all
  vars:
    REPO: https://tangled.org/solopbc.org/rookery
  tasks:
    - import_tasks: tasks/compfuzor.includes
