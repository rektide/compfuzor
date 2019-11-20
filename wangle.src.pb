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
        mkdir -p wangle/build
        cd wangle/build
        fizz_DIR="${FIZZ_CMAKE}" \
          cmake ..
        make
        make install DESTDIR="${INSTALL_DIR}"
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
    ENV:
      FBTHRIFT_CMAKE: "${TBTHRIFT_DIR}${LIBDIR}fbthrift"
      FIZZ_CMAKE: "${FIZZ_DIR}${LIBDIR}fizz"
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
