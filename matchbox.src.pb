---
- hosts: all
  vars:
    TYPE: matchbox
    REPO: https://github.com/coreos/matchbox
  tasks:
  - include: tasks/compfuzor.includes type=src
