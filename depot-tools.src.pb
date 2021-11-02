---
- hosts: all
  vars:
    TYPE: depot-tools
    INSTANCE: git
    REPO: https://chromium.googlesource.com/chromium/tools/depot_tools.git
  tasks:
  - include: tasks/compfuzor.includes type=src
