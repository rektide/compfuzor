---
- hosts: all
  vars:
    TYPE: arapi
    INSTANCE: git
    REPO: https://github.com/aparapi/aparapi
  tasks:
  - includes: tasks/compfuzor.includes type=src
