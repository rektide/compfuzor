---
- hosts: all
  vars:
    REPOS: https://github.com/badlogic/pi-mono
  tasks:
    - import_tasks: tasks/compfuzor.includes
