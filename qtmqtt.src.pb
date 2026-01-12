---
- hosts: all
  vars:
    REPO: https://github.com/qt/qtmqtt
    CMAKE: True
    CMAKE_INSTALL: --prefix /usr/local
  tasks:
    - import_tasks: tasks/compfuzor.includes
