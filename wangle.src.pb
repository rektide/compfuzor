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
        mkdir -p build
        cd build
        fizz_DIR="{{fizz}}/usr/local/lib/cmake/fizz" \
          cmake ..
        make
        make install DESTDIR="${INSTALL_DIR}"
    ENVS:
      INSTALL_DIR: "{{OPT}}"
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
