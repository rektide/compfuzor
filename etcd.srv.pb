---
- hosts: all
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: main
    VAR_DIR: True
    BIN_DIRS: True
    SYSTEMD_SERVICE: True
  tasks:
  - include: tasks/compfuzor.includes type=srv
