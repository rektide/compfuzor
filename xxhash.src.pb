---
- hosts: all
  gather_facts: False
  vars:
    TYPE: xxhash
    INSTANCE: git 
    REPO: https://github.com/Cyan4973/xxHash
  tasks:
  - include: tasks/compfuzor.includes type=src
