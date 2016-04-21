---
- hosts: all
  vars:
    TYPE: kubernetes
    INSTANCE: main
  tasks:
  - include: tasks/compfuzor.includes
