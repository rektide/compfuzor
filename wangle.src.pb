---
- hosts: all
  vars:
    TYPE: wangle
    INSTANCE: git
    REPO: https://github.com/facebook/wangle
    OPT_DIR: true
    BINS:
    - name: build.sh
      basedir: "{{SRC}}/wangle"
      run: True
      content: |
        fizz_DIR="{{fizz}}/usr/local/lib/cmake/fizz" \
          cmake .
        make
        sudo make install DESTDIR="{{OPT}}"
    PKGS:
    - libevent-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libboost-dev
    - libdouble-conversion-dev
    - zlib1g-dev
    fizz: "{{OPTS_DIR}}/fizz-git"
  tasks:
  - include: tasks/compfuzor.includes type=src
