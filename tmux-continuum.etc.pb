---
- hosts: all
  vars:
    ETC_FILES:
      - name: 99-continuum.conf
        content: |
          # Requires tmux-resurrect. Install tmux-resurrect.etc.pb as well.
          # Keep Continuum last in the plugin list, after any status-line theme.
          set -g @plugin 'tmux-plugins/tmux-continuum'
          # Ahiru otherwise loads plugins in parallel, racing themes/Resurrect.
          set -g @tpm-parallel 'false'
          # Save periodically; restore only via Resurrect's restore-session.sh.
          set -g @continuum-restore 'off'
          set -g @continuum-save-interval '15'
          # Automatic saves require the tmux status line to remain enabled.
    BINS:
      - name: install-tmux.sh
        compose: False
        basedir: False
        content: |
          set -eu
          HOST=${1:?usage: install-tmux.sh HOST_DEPLOYMENT_DIR}
          exec "$HOST/bin/config-remote.mjs" put tmux/plugins "$DIR/etc/99-continuum.conf"
  tasks:
    - import_tasks: tasks/compfuzor.includes
