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
        mkdir -p build_
        cd build_
        fizz_DIR="${FIZZ_CMAKE}" \
        folly_DIR="${FOLLY_CMAKE}" \
          cmake ..
        make
        make install DESTDIR="${INSTALL_DIR}"
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
      FOLLY_DIR: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
    ENV:
      FIZZ_CMAKE: "${FIZZ_DIR}${LIBDIR}fizz"
      FOLLY_CMAKE: "${FOLLY_DIR}${LIBDIR}folly"
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
