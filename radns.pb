---
- hosts: all
  vars:
    TYPE: radns
    INSTANCE: main
    VAR_DIR: True
    SYSTEMD_EXEC: "/usr/bin/env radns -f {{VAR}}/resolv.conf -v"
  tasks:
  - include: tasks/compfuzor.includes type=opt
