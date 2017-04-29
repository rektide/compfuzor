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
    - erlang-reltool
    - libicu-dev
    - libmozjs185-dev
    - libcurl4-openssl-dev
    # docs- kind of weighty-
    - python-sphinx
    - help2man
    - gnupg
    - rust-lldb
    DIRS:
    - rel/couchdb
    BINS:
    - name: build.sh
      run: '{{ not lookup("fileexists", SRC + "rel/couchdb")}}'
      exec:
      - "./configure #--disable-docs"
      - "make release"
      - "ln -sf `pwd`/rel/couchdb/* '{{OPT}}'/"
      - "(cd rel;tar -czf ../couchdb.tgz couchdb)"
  tasks:
  - include: tasks/compfuzor.includes type=src
