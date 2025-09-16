---
- hosts: all
  vars:
    TYPE: ssh-agent
    INSTANCE: main
    ETC_FILES:
      - name: ssh-agent.service
        content: |
          [Unit]
          Description=OpenSSH key agent
          ConditionEnvironment=!SSH_AGENT_PID
          Wants=dbus.socket
          After=dbus.socket
          Before=graphical-session-pre.target

          [Service]
          Type=simple
          Environment=SSH_AUTH_SOCK=%t/ssh-agent.sock SSH_AGENT_PID
          ExecStart=/usr/bin/ssh-agent -D -a ${SSH_AUTH_SOCK}
          #ExecStartPost=/usr/bin/systemctl --user set-environment SSH_AGENT_PID=${SYSTEMD_EXEC_PID} SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
          ExecStartPost=/usr/bin/dbus-update-activation-environment --verbose --systemd SSH_AGENT_PID=${SYSTEMD_EXEC_PID} SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
          ExecStop=/usr/bin/dbus-update-activation-environment --verbose SSH_AGENT_PID= SSH_AUTH_SOCK=
          ExecStop=/usr/bin/systemctl --user unset-environment SSH_AGENT_PID SSH_AUTH_SOCK
          SuccessExitStatus=2

          [Install]
          WantedBy=default.target
      - name: ssh-agent-env.source
        content: |
          #export $(systemctl --user show-environment|grep SSH_AUTH_SOCK)
          # semi-hardcode for speed, & maybe race-conditions?
          export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent.socket
    ENV:
      SSH_AUTH_SOCK: "$XDG_RUNTIME_DIR/ssh-agent.sock"
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          mkdir -p ~/.config/systemd/user
          ln -sf ${DIR:-{{DIR}}}/etc/ssh-agent.service ~/.config/systemd/user/
          systemctl --user daemon-reload
          systemctl --user enable --now ssh-agent

          block-in-file -n ${NAME:-{{NAME}}} -i {{DIR}}/etc/ssh-agent-env.source -o ~/.zshrc
  tasks:
    - import_tasks: tasks/compfuzor.includes

