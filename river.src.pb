---
- hosts: all
  vars:
    TYPE: river
    INSTANCE: git
    REPO: https://codeberg.org/river/river.git
    PKGS:
      - libwlroots-0.18-dev
    ENV:
      BUILD_DIR: "{{BUILD_DIR}}"
    BINS:
      - name: build.sh
        exec: |
          zig build -Doptimize=ReleaseSafe --prefix $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes
