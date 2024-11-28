---
- hosts: all
  vars:
    TYPE: wmenu
    INSTANCE: git
    REPO: https://codeberg.org/adnano/wmenu
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          meson setup $BUILD_DIR
          ninja -C $BUILD_DIR
      - name: install.sh
        exec: |
          meson -C $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes
