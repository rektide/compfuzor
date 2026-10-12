---
- hosts: all
  vars:
    ETC_FILES:
      - name: continuum.conf
        content: |
          # Requires tmux-resurrect. Install tmux-resurrect.etc.pb as well.
          # Keep Continuum last in the plugin list, after any status-line theme.
          set -g @plugin 'tmux-plugins/tmux-continuum'
          # Save periodically; restoring is always manual: prefix + Ctrl-r.
          set -g @continuum-restore 'off'
          set -g @continuum-save-interval '15'
          # Automatic saves require the tmux status line to remain enabled.
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
          # Load after Resurrect (10), before TPM init (100).
          block-in-file -n "${NAME:-{{NAME}}}" -i "${DIR}/etc/continuum.conf" -o "$TMUX_CONF" --create true --anchor eof:20
          # Source TMUX_CONF in tmux, then press prefix + I to install via TPM.
  tasks:
    - import_tasks: tasks/compfuzor.includes
