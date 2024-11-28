---
- hosts: all
  vars:
    TYPE: rofi-wayland
    INSTANCE: git
    REPO: https://github.com/lbonn/rofi
    ENV:
      BUILD_DIR: "{{BUILD_DIR}}"
    BINS:
      - name: build.sh
        exec: |
          git submodule update --init
          meson setup $BUILD_DIR
          ninja -C $BUILD_DIR
      - name: install.sh
        sudo: True
        exec: |
          meson -C $BUILD_DIR install #--prefix=$DIR
    PKGS:
      - libmpdclient-dev
      - libnl-3-dev
      - libstartup-notification0-dev
      - libxcb-cursor-dev
      - libxcb-ewmh-dev
      - libxcb-icccm4-dev
      - libxcb-imdkit-dev
      - libxcb-util-dev
      - libxcb-util0-dev
      - libxkbcommon-x11-dev
      - wayland-protocols
  tasks:
    - import_tasks: tasks/compfuzor.includes
