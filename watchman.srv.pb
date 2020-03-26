---
- hosts: all
  vars:
    TYPE: watchman
    INSTANCE: main
    SYSTEMD_EXEC: "{{WATCHMAN_BIN}} --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/socket --logfile={{VAR}}/log"
    WATCHMAN_BIN: "{{OPTS_DIR}}/watchman-git/bin/watchman"
    VAR_DIR: True
    VAR_FILE:
    - name: state
      content: "{}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
