---
- hosts: all
  vars:
    TYPE: urserver
    INSTANCE: main
    SYSTEMD_EXEC: "/usr/local/bin/urserver"
    SYSTEMD_WANTED_BY: multi-user.target
  tasks:
  - include: tasks/compfuzor.includes type=srv
