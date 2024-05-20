---
- hosts: all
  vars:
    TYPE: npupnp
    INSTANCE: git
    REPO: https://framagit.org/medoc92/npupnp
    PKGS:
      - libgcrypt20-dev
      - libmicrohttpd-dev
      - gnutls-dev
    BINS:
      - name: build.sh
        run: True
        basedir: True
        content: |
          mkdir -p build
          cd build
          #meson setup --prefix=usr . ../meson.build
          meson setup $(pwd) .. --reconfigure
          ninja
      - name: install.sh
        basedir: build
        content: |
          sudo meson install
  tasks:
    - include: tasks/compfuzor.includes type=src
