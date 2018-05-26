---
- hosts: all
  vars:
    TYPE: fbthrift
    INSTANCE: git
    REPO: https://github.com/facebook/fbthrift
    PKGS:
    - flex
    - bison
    - libboost-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libmstch-dev
    OPT_DIR: True
    BINS:
    - name: build.sh
      basedir: True
      run: True
      content: |
        fizz_DIR="{{fizz}}/usr/local/lib/cmake/fizz" \
          folly_DIR="{{folly}}/usr/local/lib/cmake/folly" \
          wangle_DIR="{{wangle}}/usr/local/lib/cmake/wangle" \
          cmake .
          make
          sudo make install DESTDIR="{{OPT}}"
    fizz: "{{OPTS_DIR}}/fizz-git"
    folly: "{{OPTS_DIR}}/folly-git"
    wangle: "{{OPTS_DIR}}/wangle-git"
  tasks:
  - include: tasks/compfuzor.includes type=src