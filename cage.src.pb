---
- hosts: all
  vars:
    TYPE: cage
    INSTANCE: git
    REPO: https://github.com/Hjdskes/cage
    PKGS:
    - libwlroots-dev
    BINS:
    - name: build.sh
      run: true
      exec: |
        meson build
        ninja -C build
        cd build
        ninja install
    - name: cage
      global: true
      exists: true
  tasks:
  - include: tasks/compfuzor.includes type=src
