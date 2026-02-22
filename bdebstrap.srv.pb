---
- hosts: all
  vars:
    TYPE: bdebstrap
    INSTANCE: main
  tasks:
    - import_tasks: tasks/compfuzor.includes
