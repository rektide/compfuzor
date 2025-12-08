---
- hosts: all
  vars:
    TYPE: jujutsu
    INSTANCE: git
    REPO: https://github.com/jj-vcs/jj
    ENV: True
    TOOL_VERSIONS:
      rust: True
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
  tasks:
    - import_tasks: tasks/compfuzor.includes
