---
- hosts: all
  vars:
    TYPE: jujutsu
    INSTANCE: git
    REPO: https://github.com/jj-vcs/jj
    ENV: True
    TOOL_VERSIONS:
      rust: True
    ETC_FILES:
      - name: watchman.toml
        content: |
          [fsmonitor]
          backend = "watchman"
          watchman.register-snapshot-trigger = true
      - name: snapshot.toml
        content: |
          [snapshot]
          #auto-update-stale = true
    BINS:
      - name: build.sh
        content: |
          cargo build --release
      - name: install.sh
        content: |
          ln -sfv "$(pwd)/target/release/jj" $GLOBAL_BINS_DIR
      - name: install-user.sh
        content: |
          cargo install --path .
      - name: install-config.sh
        content: |
          CONFD_DIR="$HOME/.config/jj/conf.d"
          mkdir -p "$CONFD_DIR"

          for config_file in "$(pwd)"/etc/*.toml; do
            ln -sfv "$config_file" "$CONFD_DIR/"
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
