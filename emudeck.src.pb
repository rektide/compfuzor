---
- hosts: all
  vars:
    TYPE: emudeck
    INSTANCE: git
    REPO: https://github.com/dragoonDorise/EmuDeck
  tasks:
    - import_tasks: tasks/compfuzor.includes
