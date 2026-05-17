---
- hosts: all
  vars:
    REPO: https://codeberg.org/x3ro/ahiru-tpm
    RUST: True
    ETC_FILES:
      - name: ahiru-plugins.conf
        content: |
          # List of plugins (install by running `ahiru-tpm install`)
          set -g @plugin 'tmux-plugins/tmux-sensible'
      - name: ahiru-run.conf
        content: |
          # Initialize Ahiru-TPM (keep this line at the very bottom of tmux.conf)
          run 'ahiru-tpm init'
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          if [ -d ~/.config/tmux ]; then
            TMUX_CONF=~/.config/tmux/tmux.conf
          else
            TMUX_CONF=~/.tmux.conf
          fi
          block-in-file -n "${NAME:-{{NAME}}}-plugins" -i ${DIR}/etc/ahiru-plugins.conf -o "$TMUX_CONF"
          block-in-file -n "${NAME:-{{NAME}}}-run" -i ${DIR}/etc/ahiru-run.conf -o "$TMUX_CONF" --after EOF
  tasks:
    - import_tasks: tasks/compfuzor.includes
