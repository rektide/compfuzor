---
- hosts: all
  vars:
    TYPE: upmpdcli
    INSTANCE: git
    REPO: https://framagit.org/medoc92/upmpdcli
    PKGS:
      - libjsoncpp-dev
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          meson setup $BUILD_DIR
          ninja -C $BUILD_DIR
      - name: install.sh
        exec: |
          ninja -C $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes
