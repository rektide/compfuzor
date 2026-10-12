---
- hosts: all
  vars:
    ETC_FILES:
      - name: 80-resurrect.conf
        content: |
          set -g @plugin 'tmux-plugins/tmux-resurrect'
          # A space disables bindings; an empty string re-enables defaults.
          set -g @resurrect-save ' '
          set -g @resurrect-restore ' '
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-dir '~/.local/share/tmux/resurrect'
    BINS:
      - name: install-tmux.sh
        compose: False
        basedir: False
        content: |
          # Explicit host deployment: either tpm-ahiru or tmux-tpm.
          set -eu
          HOST=${1:?usage: install-tmux.sh HOST_DEPLOYMENT_DIR}
          exec "$HOST/bin/config-remote.mjs" put tmux/plugins "$DIR/etc/80-resurrect.conf"
      - name: restore-session.sh
        basedir: False
        content: |
          set -eu
          if [ -z "${TMUX:-}" ]; then
            echo "restore-session.sh: run from inside a tmux session" >&2
            exit 1
          fi
          RESTORE_SCRIPT=$(tmux show-option -gqv @resurrect-restore-script-path)
          if [ -z "$RESTORE_SCRIPT" ] || [ ! -f "$RESTORE_SCRIPT" ]; then
            echo "restore-session.sh: install and initialize tmux-resurrect with your plugin manager first" >&2
            exit 1
          fi
          # Quote for tmux run-shell's shell, including paths with spaces/quotes.
          printf -v RESTORE_COMMAND '%q' "$RESTORE_SCRIPT"
          tmux run-shell "$RESTORE_COMMAND"
  tasks:
    - import_tasks: tasks/compfuzor.includes
