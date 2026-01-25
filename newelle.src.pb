---
- hosts: all
  vars:
    REPO: https://github.com/qwersyk/Newelle
    PYTHON: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
