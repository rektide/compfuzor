---
- hosts: all
  vars:
    REPO: https://github.com/jj-vcs/jj
    RUST: True
    ETC_FILES:
      - name: watchman.toml
        content: |
          # jujutsu
          #[fsmonitor]
          #backend = "watchman"
          #watchman.register-snapshot-trigger = true
      - name: snapshot.toml
        content: |
          [snapshot]
          auto-update-stale = true
    BINS:
      - name: install-config.sh
        content: |
          CONFD_DIR="$HOME/.config/jj/conf.d"
          mkdir -p "$CONFD_DIR"

          for config_file in "$(pwd)"/etc/*.toml; do
            ln -sfv "$config_file" "$CONFD_DIR/"
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
