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
          block-in-file -n "${NAME:-{{NAME}}}-plugins" -i ${DIR}/etc/tpm-plugins.conf -o ~/.tmux.conf
          block-in-file -n "${NAME:-{{NAME}}}-run" -i ${DIR}/etc/tmp-run.conf -o ~/.tmux.conf --after EOF
  tasks:
    - import_tasks: tasks/compfuzor.includes
