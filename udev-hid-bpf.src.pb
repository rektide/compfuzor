---
- hosts: all
  vars:
    TYPE: udev-hid-bpf
    INSTANCE: git
    REPO: https://gitlab.freedesktop.org/libevdev/udev-hid-bpf.git
    PKGS:
      - libbpf-dev
    ENV:
      BUILD_DIR: "{{BUILD_DIR}}"
    BINS:
      - name: build.sh
        exec: |
          meson setup $BUILD_DIR
          ninja -C $BUILD_DIR compile
      - name: install.sh
        exec: |
          ninja -C $BUILD_DIR install
  tasks:
    - import_tasks: tasks/compfuzor.includes
