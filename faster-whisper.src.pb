---
- hosts: all
  vars:
    REPO: https://github.com/SYSTRAN/faster-whisper
  tasks:
    - import_tasks: tasks/compfuzor.includes
