---
- hosts: all
  vars:
    TYPE: zx
    INSTANCE: git
    REPO: https://github.com/google/zx
  tasks:
  - include: tasks/compfuzor.includes type=src
