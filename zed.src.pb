---
- hosts: all
  vars:
    TYPE: zed
    INSTANCE: git
    REPO: https://github.com/zed-industries/zed
    ENV:
      DO_STARTUP_NOTIFY: true
      APP_CLI: zed
      APP_ICON: zed
      APP_ARGS: '%U'
      APP_NAME: 'Zed Devel'
      GLOBAL_SHARE_DIR: /usr/share
      SUFFIX: -dev
    ETC_FILES:
      - name: tool-versions
        content: |
          rust 1
          ninja 1
          cmake 4
          # used system clang instead
          #clang 20
    BINS:
      - name: build.sh
        exec: |
          [ ! -f .tool-versions ] && ln -s etc/tool-versions .tool-versions
          cargo build --release --package=zed --package=cli --package=remote_server
      - name: install.sh
        basedir: True
        content: |
          ln -sf $(pwd)/target/release/zed $GLOBAL_BINS_DIR/zed
          ln -sf $(pwd)/crates/zed/resources/app-icon${SUFFIX}.png $GLOBAL_SHARE_DIR/icons/hicolor/512x512/apps/zed.png
          ln -sf $(pwd)/crates/zed/resources/app-icon${SUFFIX}@2x.png $GLOBAL_SHARE_DIR/icons/hicolor/1024x1024/apps/zed.png
          envsubst < "crates/zed/resources/zed.desktop.in" > $GLOBAL_SHARE_DIR/applications/zed${SUFFIX}.desktop
    # this is informational only at this point, no compfuzor code does anything with this
    ARCH_PKGS:
      - alsa-lib
      #- base-devel
      - clang
      - glibc
      - libxau
      - libxcb
      - libxdmcp
      - linux-api-headers
      - mold
      - xorgproto
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
