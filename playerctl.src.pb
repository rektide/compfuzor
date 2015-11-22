---
- hosts: all
  vars:
    TYPE: playerctl
    INSTANCE: git
    REPO: https://github.com/acrisci/playerctl
    MAKE_AUTOCONF: True
    BUILD_DIR: "{{SRC}}"
    PKGS:
    - gtk-doc-tools
    - gobject-introspection
  tasks:
  - include: tasks/compfuzor.includes type=src
