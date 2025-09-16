---
- hosts: all
  vars:
    TYPE: ssh-agent
    INSTANCE: main
    ETC_FILES:
      - name: on-basic-target.conf
        content: |
          [Service]
          Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket

          [Install]
          WantedBy=basic.target
      - name: ssh-agent-env.source
        content: |
          #export $(systemctl --user show-environment|grep SSH_AUTH_SOCK)
          # semi-hardcode for speed
          export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent.socket
    ENV:
      hi: ho
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          mkdir -p ~/.config/systemd/user
          ln -s ${DIR:-{{DIR}}}/etc/on-basic-target.conf ~/.config/systemd/user/
          systemctl --user daemon-reload
          systemctl --user enable --now ssh-agent

          block-in-file -n ${NAME:-{{NAME}}} -i {{DIR}}/etc/ssh-agent-env.source -o ~/.zshrc
  tasks:
    - import_tasks: tasks/compfuzor.includes

