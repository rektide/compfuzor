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
        #./autogen.sh
        fizz_DIR="{{fizz}}/usr/local/lib/cmake/fizz" \
          FBThrift_dir="{{fbthrift}}/usr/local/lib/cmake/fbthrift" \
          wangle_DIR="{{wangle}}/usr/local/lib/cmake/wangle" \
          cmake . 
    PKGS:
    - libelf-dev
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
    fizz: "{{OPTS_DIR}}/fizz-git"
    fbthrift: "{{OPTS_DIR}}/fbthrift-git"
    wangle: "{{OPTS_DIR}}/wangle-git"
  tasks:
  - include: tasks/compfuzor.includes type=src
