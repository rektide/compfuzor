---
- hosts: all
  vars:
    TYPE: couchdb
    INSTANCE: main
    couchdb_dir: "{{OPTS_DIR}}/couchdb-git"

    SYSTEMD_EXEC: "{{DIR}}/opt/bin/couchdb -A '{{ETC}}'"
    SYSTEMD_CWD: "{{DIR}}/opt"
    ENV:
      UUID: True
      HOME: "{{DIR}}"
    VAR_DIRS:
    - db
    - view-index
    LINKS:
      opt: "{{couchdb_dir}}"
    ETC_DIRS:
    - local.d
    ETC_FILES:
    - name: local.d/var.ini
      content: "[couchdb]\nuuid = {{UUID}}\ndatabase_dir = {{VAR}}/db\nview_index_dir = {{VAR}}/view-index"
  tasks:
  - include: tasks/compfuzor.includes type=srv
