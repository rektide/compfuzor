---
- hosts: all
  vars:
    REPO: https://github.com/fmtlib/fmt
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
