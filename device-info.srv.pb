---
- hosts: all
  vars:
    TYPE: device-info
    INSTANCE: main
    SYSTEMD_DNSSD: {}
  tasks:
  - include: tasks/compfuzor.includes type=srv
