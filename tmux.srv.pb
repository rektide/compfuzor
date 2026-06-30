---
- hosts: all
  vars:
    TYPE: tmux
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_LINK: False
    SYSTEMD_UNITS:
      Description: tmux server
    SYSTEMD_SERVICES:
      Type: forking
      ExecStart: /usr/bin/tmux start-server
      ExecStop: /usr/bin/tmux kill-server
      SyslogIdentifier: tmux
      OOMScoreAdjust: -1000
      OOMPolicy: continue
      PassEnvironment:
        - DISPLAY
        - WAYLAND_DISPLAY
        - XAUTHORITY
        - SSH_AUTH_SOCK
        - SSH_AGENT_PID
        - DBUS_SESSION_BUS_ADDRESS
        - XDG_RUNTIME_DIR
    SYSTEMD_INSTALLS:
      WantedBy: default.target
    BINS:
      - name: install-user.sh
        content: |
          mkdir -p $HOME/.config/systemd/user
          ln -sfv "$(pwd)/etc/{{NAME}}.service" $HOME/.config/systemd/user/
          systemctl --user daemon-reload
          systemctl --user enable --now tmux.service
  tasks:
    - import_tasks: tasks/compfuzor.includes
