---
# meh, has dropped Wayland support, https://github.com/xrelkd/clipcat/pull/600
- hosts: all
  vars:
    TYPE: clipcat
    INSTANCE: git
    REPO: https://github.com/xrelkd/clipcat
    PKGS:
      - protobuf-compiler
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        exec: |
          cargo install --path clipcatd
          cargo install --path clipcatctl
          cargo install --path clipcat-menu
  tasks:
    - import_tasks: tasks/compfuzor.includes
