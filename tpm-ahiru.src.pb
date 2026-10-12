---
- hosts: all
  vars_files:
    - vars/tmux-plugins.yaml
  vars:
    #REPO: https://codeberg.org/x3ro/ahiru-tpm
    REPO: https://github.com/x3rAx/ahiru-tpm
    RUST: True
    ETC_FILES:
      - name: tmux-plugins.d/00-ahiru.conf
        content: |
          # List of plugins (install by running `ahiru-tpm install`)
          set -g @plugin 'tmux-plugins/tmux-sensible'
          set -g @plugin 'tmux-plugins/tmux-yank'
          set -g @plugin 'rektide/tpm-desktop-vars'
      - name: tmux-run.conf
        content: |
          # Initialize Ahiru-TPM (keep this line at the very bottom of tmux.conf)
          run -b 'ahiru-tpm init'
    BINS:
      - name: install-user.sh
        basedir: False
        src: ../tmux/install-manager.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
