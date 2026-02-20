---
- hosts: all
  vars:
    REPO: https://github.com/QuentinFuxa/WhisperLiveKit
  tasks:
    - import_tasks: tasks/compfuzor.includes
