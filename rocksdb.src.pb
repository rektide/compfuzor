---
- hosts: all
  vars:
    TYPE: rocksdb
    INSTANCE: 5.1.4
    TGZ: "https://github.com/facebook/rocksdb/archive/v{{INSTANCE}}.tar.gz"
    BINS:
    - name: build.sh
      exec: |
        make shared_lib
        sudo make install
  tasks:
  - include: tasks/compfuzor.includes type=src
