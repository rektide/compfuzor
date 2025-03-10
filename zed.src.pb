---
- hosts: all
  vars:
    TYPE: zed
    INSTANCE: git
    REPO: https://github.com/zed-industries/zed
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        basedir: True
        exec: |
          ln -sf $(pwd)/target/release/zed $GLOBAL_BINS_DIR/
    PKGS:
      - gcc
      - g++
      - libasound2-dev
      - libfontconfig-dev
      - libwayland-dev
      - libxkbcommon-x11-dev
      - libssl-dev
      - libzstd-dev
      - libvulkan1
      - libgit2-dev
      - make
      - cmake
      - clang
      - jq
      - netcat-openbsd
      - git
      - curl
      - gettext-base
      - elfutils
      - libsqlite3-dev
      - musl-tools
      - musl-dev
      - build-essential
  tasks:
    - import_tasks: tasks/compfuzor.includes
