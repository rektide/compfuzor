# https://developers.facebook.com/blog/post/2021/09/21/below-time-travelling-resource-monitoring-tool/
---
- hosts: all
  vars:
    TYPE: below
    INSTANCE: git
    REPO: https://github.com/facebookincubator/below
    BINS:
      - name: build.sh
        basedir: True
        exec: |
          cargo build --release
      - name: install.sh
        basedir: True
        exec: |
          #ln -s $(pwd)/target/release/below $GLOBAL_BINS_DIR/
          # so we don't have to reconfigure below.service
          ln -sf $(pwd)/target/release/below /usr/bin/below
          ln -sf $(pwd)/etc/below.service $SYSTEMD_UNIT_DIR/
          systemctl enable below.service
    PKGS:
      - zlib1g-dev
      - libelf-dev
      - libncurses-dev
      - libssl-dev
    ENV:
      CLANG: clang-18
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
      SYSTEMD_UNIT_DIR: "{{SYSTEMD_UNIT_DIR}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
