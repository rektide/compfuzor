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
      - name: jj.conf
        content: |
          [fsmonitor]
          backend = "watchman"
          watchman.register-snapshot-trigger = true

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
      - name: install-config
        content: |
          TARGET=config.toml
          [ -e config.toml ] || TARGET="$HOME/.config/jj/config.toml"
          ./mergeToml $TARGET $(pwd)/etc/jj.conf
      - name: 'mergeToml'
        src: '../mergeToml'
  tasks:
    - import_tasks: tasks/compfuzor.includes
