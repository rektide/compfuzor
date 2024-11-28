---
- hosts: all
  vars:
    TYPE: fuzzel
    INSTANCE: git
    REPO: https://codeberg.org/dnkl/fuzzel
    PKGS:
      - check
      - libfcft-dev
      - libpng-dev
      - librsvg2-dev
      - libtllist-dev
      - scdoc
    ENV:
      BUILD_DIR: "{{BUILD_DIR}}"
    BINS:
      - name: build.sh
        exec: |
          mkdir -p $BUILD_DIR
          meson setup $BUILD_DIR \
            --buildtype=release \
            -Denable-cairo=enabled \
            -Dpng-backend=libpng \
            -Dsvg-backend=librsvg
          ninja -C $BUILD_DIR
      - name: install.sh
        exec: |
          sudo meson -C $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes
