---
- hosts: all
  vars:
    TYPE: afk-dim
    INSTANCE: main
    USERMODE: True
    SYSTEMD_SERVICE: True
    SYSTEMD_UNITS:
      After: graphical-session.target
      Wants: graphical-session.target
    SYSTEMD_SERVICES:
      ExecStart: /usr/local/bin/afk-dim
    SYSTEMD_INSTALLS:
      WantedBy: graphical-session.target
    ENV:
      NIRI_SOCKET: "$XDG_RUNTIME_DIR/niri.sock"
  tasks:
    - import_tasks: tasks/compfuzor.includes
