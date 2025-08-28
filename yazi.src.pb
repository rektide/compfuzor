---
- hosts: all
  vars:
    TYPE: yazi
    INSTANCE: git
    REPO: https://github.com/sxyazi/yazi
    ENV: {}
    BINS:
      - name: build.sh
        contents: |
          cargo build --release --locked
      - name: install.sh
        contents: |
          ln -s target/release/yazi ${GLOBAL_BINS_DIR}/yazi
    PKGS:
     - ffmpeg
     - 7zip
     - jq
     - poppler-utils
     - fd-find
     - ripgrep
     - fzf
     - zoxide
     - imagemagick
  tasks:
    - import_tasks: tasks/compfuzor.includes

