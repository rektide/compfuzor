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
      - libgtk-4-dev
      - libgtk4-layer-shell-dev
      - gettext
      - libxml2-utils
    ENV: True
    BINS:
      - name: build.sh
        exec: zig build -Doptimize=ReleaseFast
      - name: global.sh
        exec: |
          zig build -Doptimize=ReleaseFast -p $GLOBAL_BINS_DIR/.. $*
      - name: install.sh
        exec: |
          ln -s $(pwd)/zig-out/bin/ghostty ${GLOBAL_BINS_DIR}/ghostty
      - name: infocmp-remote.sh
        exec: |
          # https://ghostty.org/docs/help/terminfo
          # note, this only works if actively using ghostty. would like to fix?
          # and macos needs homebrew infocmp
          #infocmp -x | ssh $1 -- tic -x -
          infocmp -x | ssh $1 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
  tasks:
    - import_tasks: tasks/compfuzor.includes
