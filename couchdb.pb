---
- hosts: all
  vars:
    TYPE: couchdb
    INSTANCE: main
    PKGS:
    - couchdb
    COUCHDB_BIN: /usr/bin/couchdb
    SYSTEMD_EXEC: "{{COUCHDB_BIN}}"
    SYSTEMD_CWD: "{{VAR}}"
    ETC_DIR: True
    VAR_DIR: True
  tasks:
  - include: tasks/compfuzor.includes type=srv
