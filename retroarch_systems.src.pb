---
- hosts: all
  vars:
    TYPE: retroarch_systems
    INSTANCE: git
    REPO: https://github.com/Abdess/retroarch_system
  tasks:
    - import_tasks: tasks/compfuzor.includes
