---
- hosts: all
  vars:
    TYPE: glamorous-toolkit
    INSTANCE: git
    REPO: https://github.com/feenkcom/gtoolkit
  tasks:
    - include: tasks/compfuzor.includes type=src

