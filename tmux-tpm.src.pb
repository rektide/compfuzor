---
- hosts: all
  vars_files:
    - vars/tmux-plugins.yaml
  vars:
    REPO: https://github.com/tmux-plugins/tpm
    ETC_FILES:
      - name: tmux-plugins.d/00-tpm.conf
        content: |
          # List of plugins
          set -g @plugin 'tmux-plugins/tpm'
          set -g @plugin 'tmux-plugins/tmux-sensible'
      - name: tmux-run.conf
        content: |
          # this really must come at the end
          run '{{DIR}}/tpm'
    BINS:
      - name: install-user.sh
        basedir: False
        src: ../tmux/install-manager.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
