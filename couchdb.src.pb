---
- hosts: all
  vars:
    TYPE: couchdb
    INSTANCE: git
    REPO: https://github.com/apache/couchdb
    OPT_DIR: True
    PKGS:
    - erlang
    - build-essential
    - pkg-config
    - erlang
    - libicu-dev
    - libmozjs185-dev
    - libcurl4-openssl-dev
    BINS:
    - name: build.sh
      exec:
      - "./configure --prefix '{{ OPT_DIR }}"
      - "make release"
  tn:asks:
  - include: tasks/compfuzor.includes type=src
