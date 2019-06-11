---
- hosts: all
  vars:
    TYPE: foundationdb
    INSTANCE: git
    REPOS:
      foundationdb: https://github.com/apple/foundationdb
      fdb-document-layer: https://github.com/FoundationDB/fdb-document-layer
      fdb-record-layer: https://github.com/FoundationDB/fdb-record-layer
    BINS:
    - name: build.sh
      exec: |
        ./bin/build-foundationdb.sh
    - name: build-foundationdb.sh
      basedir: "{{GIT_DIR}}/foundationdb"
      exec: |
        mkdir -f build
        cd build
        #cmake -DBOOST_ROOT=<PATH_TO_BOOST> -DLibreSSL_ROOT=<> <PATH_TO_FOUNDATIONDB_DIRECTORY>
        cmake ..
        make
    - name: build-document-layer.sh
      basedir: "{{GIT_DIR}}/fdb-document-layer"
      exec: |
        mkdir -f build
    - name: build-document-layer.sh
      basedir: "{{GIT_DIR}}/fdb-document-layer"
      exec: |
        mkdir -f build
  tasks:
  - include: tasks/compfuzor.includes type=src
