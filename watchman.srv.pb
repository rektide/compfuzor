---
- hosts: all
  vars:
    TYPE: watchman
    INSTANCE: main
    VAR_DIR: True
    VAR_FILES:
      - name: state
        content: "{}"
    WATCHMAN_BIN: "{{OPTS_DIR}}/watchman-git/bin/watchman"
    SYSTEMD_SERVICE: True
    SYSTEMD_SERVICES:
      ExecStart: "{{WATCHMAN_BIN}} --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/socket --logfile={{VAR}}/log"
  tasks:
    - import_tasks: tasks/compfuzor.includes
