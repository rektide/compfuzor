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
      - name: apply-user.sh
        deployment_rooted: True
        basedir: False
        content: |
          set -eu
          # Check the target server before changing configuration.
          tmux display-message -p '#{pid}' >/dev/null
          "$DIR/bin/config-assemble.sh" --definition tmux --context canonical
          "$DIR/bin/install-user.sh"
          # Apply settings before Ahiru discovers, installs and initializes plugins.
          tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/compfuzor/{{NAME}}/tmux-plugins.conf"
          ahiru-tpm install
          exec ahiru-tpm init
  tasks:
    - import_tasks: tasks/compfuzor.includes
