---
- hosts: all
  vars:
    TYPE: libpisp
    INSTANCE: git
    REPO: https://github.com/raspberrypi/libpisp
    PKGS:
     - nlohmann-json3-dev
     - cmake
     - ninja
     - meson
     - libboost-log-dev
     - libboost-system-dev
     - libboost-thread-dev
    BINS:
      - name: build.sh
        exec: |
          meson setup build
          ninja -C build
      - name: install.sh
        exec: |
          sudo ninja -C build install
  tasks:
    - include: tasks/compfuzor.includes type=src
