---
- hosts: all
  vars:
    REPO: https://github.com/linuxmobile/oxicord
  tasks:
    - import_tasks: tasks/compfuzor.includes
