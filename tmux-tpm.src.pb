---
- hosts: all
  vars:
    REPO: https://github.com/tmux-plugins/tpm
    ETC_FILES:
      - name: tpm-plugins.conf
        content: |
          # List of plugins
          set -g @plugin 'tmux-plugins/tpm'
          set -g @plugin 'tmux-plugins/tmux-sensible'
      - name: tpm-run.conf
        content: |
          # this really must come at the end
          run '{{DIR}}/tpm'
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          if [ -z "${TMUX_CONF:-}" ]; then
            if [ -f "$HOME/.tmux.conf" ]; then
              TMUX_CONF="$HOME/.tmux.conf"
            elif [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/tmux" ]; then
              TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
            else
              TMUX_CONF="$HOME/.tmux.conf"
            fi
          fi
          block-in-file -n "${NAME:-{{NAME}}}-plugins" -i "${DIR}/etc/tpm-plugins.conf" -o "$TMUX_CONF" --create true
          # Stay below separately installed plugin blocks, regardless of install order.
          block-in-file -n "${NAME:-{{NAME}}}-run" -i "${DIR}/etc/tpm-run.conf" -o "$TMUX_CONF" --create true --anchor eof:100
  tasks:
    - import_tasks: tasks/compfuzor.includes
