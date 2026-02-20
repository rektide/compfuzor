---
- hosts: all
  vars:
    REPO: https://github.com/rishikanthc/Scriberr
  tasks:
    - import_tasks: tasks/compfuzor.includes
