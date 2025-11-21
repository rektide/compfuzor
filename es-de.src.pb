---
- hosts: all
  vars:
    TYPE: es-de
    INSTANCE: git
    REPO: https://gitlab.com/es-de/emulationstation-de
  tasks:
    - import_tasks: tasks/compfuzor.includes
