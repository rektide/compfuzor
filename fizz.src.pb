---
- hosts: all
  vars:
    TYPE: fizz
    INSTANCE: git 
    REPO: https://github.com/facebookincubator/fizz
    BINS:
    - name: build.sh
      basedir: fizz
      content: |
        cmake .
        make -j $(nproc)
        make install DESTDIR={{OPT}}
    OPT_DIR: true
    PKGS:
      - libevent-dev
      - libdouble-conversion-dev
      - libgoogle-glog-dev
      - libgflags-dev
      - libiberty-dev
      - liblz4-dev
      - liblzma-dev
      - libsnappy-dev
      - zlib1g-dev
      - libjemalloc-dev
      - libsodium-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
