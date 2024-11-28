---
- hosts: all
  vars:
    TYPE: ilia
    INSTANCE: git
    REPO: https://github.com/regolith-linux/ilia
    PKGS:
      - valac
      - libjson-glib-dev
      - libtracker-sparql-3.0-dev
      - libgee-0.8-dev
      - gir1.2-gtklayershell-0.1
      - libgtk-layer-shell-dev
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          meson -C $BUILD_DIR setup
          ninja -C $BUILD_DIR
      - name: install.sh
        exec: |
          ninja -C $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes

