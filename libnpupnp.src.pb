---
- hosts: all
  vars:
    TYPE: libnpupnp
    INSTANCE: git
    REPO: https://framagit.org/medoc92/npupnp.git
    PKGS:
      - libmicrohttpd-dev
    BINS:
      - name: build.sh
        basedir: True
        exec: |
          meson setup build
          cd build
          ninja
      - name: install.sh
        become: True
        basedir: build
        exec: |
          sudo meson install
  tasks:
    - import_tasks: tasks/compfuzor.includes
