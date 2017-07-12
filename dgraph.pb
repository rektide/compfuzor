---
- hosts: all
  vars:
    TYPE: dgraph
    INSTANCE: main
    VAR_DIR: True
    SYSTEMD_EXEC: "/usr/bin/env dgraph"
    SYSTEMD_WORKING_DIRECTORY: "{{VAR}}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
