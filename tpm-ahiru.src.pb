---
- hosts: all
  vars:
    #REPO: https://codeberg.org/x3ro/ahiru-tpm
    REPO: https://github.com/x3rAx/ahiru-tpm
    RUST: True
    ETC_FILES:
      - name: ahiru-plugins.conf
        content: |
          # List of plugins (install by running `ahiru-tpm install`)
          set -g @plugin 'tmux-plugins/tmux-sensible'
          set -g @plugin 'tmux-plugins/tmux-yank'
          set -g @plugin 'rektide/tpm-desktop-vars'
          # tmux-resurrect: the save/restore engine
          set -g @plugin 'tmux-plugins/tmux-resurrect'
          # tmux-continuum: automatic periodic saving (builds on resurrect)
          set -g @plugin 'tmux-plugins/tmux-continuum'
      - name: ahiru-resurrect.conf
        content: |
          # tmux-resurrect + tmux-continuum configuration.
          # continuum still auto-saves on the interval below so snapshots exist
          # for manual restore; only auto-restore-on-server-start is disabled.
          #
          # Hotkeys (tmux-resurrect defaults):
          #   prefix + Ctrl-s   save the current tmux environment now
          #   prefix + Ctrl-r   restore the last saved environment
          # (prefix + Ctrl-r is the manual alternative to restore-session.sh)
          set -g @continuum-restore 'off'
          set -g @continuum-save-interval '15'
          set -g @resurrect-capture-pane-contents 'on'
          # Snapshot location: $XDG_DATA_HOME/tmux/resurrect. tmux-resurrect
          # only supports $HOME, $HOSTNAME and ~ in @resurrect-dir (no shell or
          # env interpolation), so $XDG_DATA_HOME is written out by its default
          # ~/.local/share.
          set -g @resurrect-dir '~/.local/share/tmux/resurrect'
      - name: ahiru-run.conf
        content: |
          # Initialize Ahiru-TPM (keep this line at the very bottom of tmux.conf)
          run -b 'ahiru-tpm init'
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
          block-in-file -n "${NAME:-{{NAME}}}-resurrect" -i ${DIR}/etc/ahiru-resurrect.conf -o "$TMUX_CONF" --after "^# ${NAME:-{{NAME}}}-plugins end"
          block-in-file -n "${NAME:-{{NAME}}}-run" -i ${DIR}/etc/ahiru-run.conf -o "$TMUX_CONF" --after EOF
      - name: restore-session.sh
        basedir: False
        content: |
          # Manually restore the most recent tmux-resurrect snapshot into the
          # running tmux server. Requires tmux-resurrect installed (run
          # install-user.sh then `ahiru-tpm install`) and an active tmux session.
          if [ -z "${TMUX:-}" ]; then
            echo "restore-session.sh: must be run from inside a tmux session" >&2
            exit 1
          fi
          _PLUGIN_DIR="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/plugins}"
          RESTORE_SCRIPT="$_PLUGIN_DIR/tmux-resurrect/scripts/restore.sh"
          if [ ! -f "$RESTORE_SCRIPT" ]; then
            echo "restore-session.sh: tmux-resurrect restore script not found:" >&2
            echo "  $RESTORE_SCRIPT" >&2
            echo "  Run install-user.sh and 'ahiru-tpm install' first." >&2
            exit 1
          fi
          tmux run-shell "$RESTORE_SCRIPT"
  tasks:
    - import_tasks: tasks/compfuzor.includes
