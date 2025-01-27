---
- hosts: all
  vars:
    TYPE: ghostty
    INSTANCE: git
    REPO: https://github.com//ghostty-org/ghostty
    PKGS:
      - libgtk-4-dev
      - libadwaita-1-dev
      - libhwy-dev
      - gcc-multilib
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: zig build -Doptimize=ReleaseFast
      - name: global.sh
        exec:
          exec: zig build -Doptimize=ReleaseFast -p $GLOBAL_BINS_DIR/..
      - name: install.sh
        exec:
          ln -s $(pwd)/zig-out/bin/ghostty ${GLOBAL_BINS_DIR}/ghostty
  tasks:
    - import_tasks: tasks/compfuzor.includes
