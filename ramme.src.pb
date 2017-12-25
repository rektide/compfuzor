---
- hosts: all
  vars:
    TYPE: ramme
    INSTANCE: git
    REPO: https://github.com/terkelg/ramme
    BINS:
    - exec: npm install
  tasks:
  - include: tasks/compfuzor.includes type=src
