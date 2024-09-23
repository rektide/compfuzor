---
- hosts: all
  vars:
    TYPE: adbfs
    INSTANCE: main
    REPO: https://github.com/zach-klippenstein/adbfs
  tasks:
    - include: tasks/compfuzor.includes type=src
