---
- hosts: all
  vars:
    TYPE: radns
    INSTANCE: git
    REPO: http://hack.org/mc/git/radns
    BINS:
    - exec: make
    - global: radns
  tasks:
  - include: tasks/compfuzor.includes type=src
