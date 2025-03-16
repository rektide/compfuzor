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
      - blueprint-compiler
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: zig build -Doptimize=ReleaseFast
      - name: global.sh
        exec: |
          exec: zig build -Doptimize=ReleaseFast -p $GLOBAL_BINS_DIR/..
      - name: install.sh
        exec: |
          ln -s $(pwd)/zig-out/bin/ghostty ${GLOBAL_BINS_DIR}/ghostty
      - name: infocmp-remote.sh
        exec: |
          # https://ghostty.org/docs/help/terminfo
          # note, this only works if actively using ghostty. would like to fix?
          # and macos needs homebrew infocmp
          infocmp -x | ssh $1 -- tic -x -
  tasks:
    - import_tasks: tasks/compfuzor.includes
