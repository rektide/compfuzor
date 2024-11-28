---
- hosts: all
  vars:
    TYPE: copyq
    INSTANCE: git
    REPO: https://github.com/hluk/CopyQ.git
    PKGS:
      - cmake
      - cmake-extras
      - extra-cmake-modules
      - libkf6statusnotifieritem-dev
      - qt6-wayland-dev
      - qt6-svg-dev
      - qt6-svg-private-dev
      - qt6-base-private-dev
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DWITH_QT6=true .
          make
      - name: install.sh
        exec: |
          sudo make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
