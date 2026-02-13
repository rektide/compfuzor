---
- hosts: all
  vars:
    REPO: https://github.com/catppuccin/tmux
    ENV:
      - TMUX_CONF_D_DIR
    ETC_FILES:
      
    BINS:
      - name: install-user.sh
        content: |
          # TODO: calculate xdg config directory for tmux here
          # and only if not set
          export TMUX_CONF_DIR=
          mkdir -p $TMUX_CONF_DIR/$TMUX_CONF_D_DIR
          ln -s $(pwd)/etc/
  tasks:
    - import_tasks: tasks/compfuzor.includes
