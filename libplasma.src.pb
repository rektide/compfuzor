---
- hosts: all
  vars:
    REPO: https://invent.kde.org/plasma/libplasma
    CMAKE: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
