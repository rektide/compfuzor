---
- hosts: all
  vars:
    TYPE: synergyc
    SYSTEMD_INSTANCED: True
    SYSTEMD_EXEC: /usr/bin/env synergyc --no-daemon %I
    USERMODE: True
  tasks:
  - include: tasks/compfuzor.includes type=srv
