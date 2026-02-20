---
- hosts: all
  vars:
    REPO: https://github.com/QuentinFuxa/NoLanguageLeftWaiting
  tasks:
    - import_tasks: tasks/compfuzor.includes
