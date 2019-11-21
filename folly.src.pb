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
        mkdir build_
        cd build_
        cmake ..
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
    - libssl-dev
    - libsnappy-dev
    - libgoogle-glog-dev
    - libiberty-dev
    - libsodium-dev
    - libaio-dev
    - libdwarf-dev
    - libboost-context-dev
    - libboost-filesystem-dev
    - libboost-program-options-dev
    - libboost-regex-dev
    - libboost-system-dev
    - libboost-thread-dev
    - libfmt-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
