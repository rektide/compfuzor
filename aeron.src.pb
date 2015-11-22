---
- hosts: all
  gather_facts: False
  vars:
    TYPE: aeron
    INSTANCE: git
    REPO: https://github.com/real-logic/Aeron
    BINS:
    - exec: './gradlew'
    - exec: './cppbuild'
      dir: 'cppbuild'
  tasks:
  - include: tasks/compfuzor.includes type=src
