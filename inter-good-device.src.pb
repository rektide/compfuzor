---
- hosts: all
  vars:
    TYPE: inter-good-device
    INSTANCE: git
    REPO: https://github.com/jauntywunderkind/inter-good-device
  tasks:
  - include: tasks/compfuzor.includes type=src
