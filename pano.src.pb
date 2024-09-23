---
- hosts: all
  vars:
    TYPE: pano
    INSTANCE: git
    REPO: https://github.com/oae/gnome-shell-pano
    PKGS:
      - libcogl-dev
      - libgsound-dev
      - libgda-5.0-dev
    BINS:
      - name: build.sh
        exec:
  tasks:
    - include: tasks/compfuzor.includes type=src
