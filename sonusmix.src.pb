---
- hosts: all
  vars:
    TYPE: sonusmix
    INSTANCE: git
    REPO: https://codeberg.org/sonusmix/sonusmix
    PKGS:
      - resvg
      - libgtk-4-dev
      - libpipewire-0.3-dev
    BINS:
      - name: cargo-prep.sh
        exec:
          # sonusmix specifies a very old version of cargo that wont build cargo make
          # so cd somewhere else
          cd /tmp
          cargo install cargo-make
          cargo install cargo-about
      - name: build.sh
        exec:
          cargo make 
  tasks:
    - import_tasks: tasks/compfuzor.includes
