---
- hosts: all
  vars:
    TYPE: xwayland-satellite
    INSTANCE: main
    REPO: https://github.com/Supreeeme/xwayland-satellite
    ENV: True
    BINS:
      - name: build.sh
        content: |
          cargo build --release -F systemd
      - name: install.sh
        content: |
          ln -sfv "$(pwd)/target/release/xwayland-satellite" $GLOBAL_BINS_DIR
  tasks:
    - import_tasks: tasks/compfuzor.includes
