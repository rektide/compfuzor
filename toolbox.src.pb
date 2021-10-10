---
- hosts: all
  vars:
    TYPE: toolbox
    INSTANCE: git
    REPO: https://github.com/containers/toolbox
    PKGS:
    - go-md2man
    - skopeo
    OPT_DIR: true
    BINS:
    - name: build.sh
      exec: |
        meson "{{OPT}}"
        ninja -C "{{OPT}}"
        ninja -C "{{OPT}}" install
  tasks:
  - include: tasks/compfuzor.includes type=src
