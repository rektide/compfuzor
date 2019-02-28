---
- hosts: all
  vars:
    TYPE: folly
    INSTANCE: git
    REPO: https://github.com/facebook/folly
    BINS:
    - name: build.sh
      run: True
      content: |
        cmake .
        make
        make DESTDIR="{{OPT}}" install
    OPT_DIR: true
    PKGS:
    - libboost-dev
    - libdouble-conversion-dev
    - libgflags-dev
    - libevent-dev
    - libbz2-dev
    - libunwind-dev
    - liblz4-dev
    - libzstd-dev
    - liblzma-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
