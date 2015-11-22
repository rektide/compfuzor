---
- hosts: all
  gather_facts: false
  vars:
    TYPE: chrome-sync-server
    INSTANNCE: git
    REPO: https://github.com/valurhrafn/chrome-sync-server
    SYSTEMD_EXEC: python sync_server.py --port 8090
  tasks:
  - include: tasks/compfuzor.includes type=src
