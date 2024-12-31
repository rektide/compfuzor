---
- hosts: all
  vars:
    TYPE: ghostty
    INSTANCE: git
    REPO: https://github.com//ghostty-org/ghostty
    PKGS:
      - libgtk-4-dev
      - libadwaita-1-dev
    ENVS:
      hi: ho
    BINS:
      - name: build.sh
        exec: zig build -Doptimize=ReleaseFast
      - name: install.sh
        exec:
          ln -s $(pwd)/zig-out/bin/ghostty ${GLOBAL_BINS_DIR}/ghostty
  tasks:
    - import_tasks: tasks/compfuzor.includes
