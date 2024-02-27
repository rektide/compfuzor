---
- hosts: all
  vars:
    TYPE: libpisp
    INSTANCE: git
    REPO: https://github.com/raspberrypi/libpisp
    PKGS:
     - nlohmann-json3-dev
     - cmake
     - ninja-build
     - meson
     - libboost-log-dev
     - libboost-system-dev
     - libboost-thread-dev
    BINS:
      - name: build.sh
        exec: |
          time meson setup build
          time ninja -C build
      - name: install.sh
        exec: |
          sudo time ninja -C build install
  tasks:
    - include: tasks/compfuzor.includes type=src
