---
- hosts: all
  vars:
    REPO: https://github.com/tmuxpack/tpack
    GO: True
    GO_BIN: tpack
    GO_TARGET: ./cmd/tpack
    ETC_FILES:
      - name: tpack-plugins.conf
        content: |
          # List of plugins
          set -g @plugin 'tmux-plugins/tmux-sensible'
      - name: tpack-run.conf
        content: |
          # Initialize tpack (keep this line at the very bottom of tmux.conf)
          run 'tpack init'
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          if [ -d ~/.config/tmux ]; then
            TMUX_CONF=~/.config/tmux/tmux.conf
          else
            TMUX_CONF=~/.tmux.conf
          fi
          block-in-file -n "${NAME:-{{NAME}}}-plugins" -i ${DIR}/etc/tpack-plugins.conf -o "$TMUX_CONF"
          block-in-file -n "${NAME:-{{NAME}}}-run" -i ${DIR}/etc/tpack-run.conf -o "$TMUX_CONF" --after EOF
  tasks:
    - import_tasks: tasks/compfuzor.includes
