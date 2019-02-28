---
- hosts: all
  vars:
    TYPE: watchman
    INSTANCE: git
    REPO: https://github.com/facebook/watchman
    BINS:
    - name: build.sh
      run: True
      content: |
        ./autogen.sh
    PKGS:
    - libevent-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libboost-dev
    - liblz4-dev
    - libsnappy-dev
    - libdwarf-dev
    - libiberty-dev
    - libaio-dev
    - libzstd-dev
    - libdouble-conversion-dev
    - zlib1g-dev
    - liblzma-dev
    - libboost-context-dev
    - libboost-chrono-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
