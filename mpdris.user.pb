---
- hosts: all
  gather_facts: False
  vars:
    TYPE: mpdris
    INSTANCE: main
    PKGS:
    - mpdris2
    SYSTEMD_EXEC: ""
    ETC_FILES:
    - mpDris2.conf
  tasks:
  - include: tasks/compfuzor.includes type=srv
