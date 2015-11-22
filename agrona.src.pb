---
- hosts: all
  gather_facts: False
  vars:
    TYPE: agrona
    INSTANCE: git
    REPO: https://github.com/real-logic/Agrona
    BINS:
    - exec: './gradlew'
  tasks:
  - include: tasks/compfuzor.includes type="src"
