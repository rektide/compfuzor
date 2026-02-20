---
- hosts: all
  vars:
    REPO: https://github.com/SYSTRAN/faster-whisper
    PYTHON: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
