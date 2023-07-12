---
- hosts: all
  vars:
    TYPE: community-solid-server
    INSTANCE: main
    OPT_DIR: true
    src: "/opt/{{TYPE}}-git"
  tasks:
    - include: tasks/compfuzor.includes type=src
