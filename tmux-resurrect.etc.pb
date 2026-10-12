---
- hosts: all
  vars:
    ETC_FILES:
      - name: resurrect.conf
        content: |
          # TPM: prefix + I installs the plugin after sourcing this config.
          set -g @plugin 'tmux-plugins/tmux-resurrect'
          # Manual controls: prefix + Ctrl-s saves; prefix + Ctrl-r restores.
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-dir '~/.local/share/tmux/resurrect'
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
          # Load after ordinary config, before Continuum (20) and TPM init (100).
          block-in-file -n "${NAME:-{{NAME}}}" -i "${DIR}/etc/resurrect.conf" -o "$TMUX_CONF" --create true --anchor eof:10
          # Source TMUX_CONF in tmux, then press prefix + I to install via TPM.
  tasks:
    - import_tasks: tasks/compfuzor.includes
