---
- hosts: all
  vars:
    TYPE: wob
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_UNITS:
      After: graphical-session.target
      Wants: graphical-session.target
    SYSTEMD_SERVICES:
      ExecStart: /usr/bin/wob
    SYSTEMD_INSTALL:
      WantedBy: graphical-session.target
      Alias: wob
    SYSTEMD_LINK: False
    BINS:
      - name: install-user-service.sh
        content: |
          ln -sfv "$(pwd)/etc/{{NAME}}.service" $HOME/.config/systemd/user/
  tasks:
    - import_tasks: tasks/compfuzor.includes
