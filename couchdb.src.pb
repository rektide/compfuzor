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
      run: '{{ not lookup("fileexists", SRC + "rel/couchdb")}}'
      exec:
      - "[ ! -e 'rel/couchdb' ] && ln -s '{{OPT}}' rel/couchdb"
      - "./configure --disable-docs"
      - "make release"
    - name: couchdb
      global: True
      src: False
      basedir: rel/couchdb/bin
      delay: postRun
  tasks:
  - include: tasks/compfuzor.includes type=src
