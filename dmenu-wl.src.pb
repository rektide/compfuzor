---
- hosts: all
  vars:
    TYPE: dmenu-wl
    INSTANCE: git
    REPO: https://github.com/nyyManni/dmenu-wayland
    PKGS:
      - libwayland-bin
      - wayland-protocols
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          meson setup $BUILD_DIR
          ninja -C $BUILD_DIR
  tasks:
    - import_tasks: tasks/compfuzor.includes
