---
- hosts: all
  vars:
    TYPE: rsocket
    INSTANCE: git
    REPO: https://github.com/rsocket/rsocket-cpp
    OPT_DIR: True
    PKGS:
    - googletest
    - libgtest-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libgmock-dev
    - google-mock
    BINS:
    - name: build.sh
      basedir: True
      content: |
        mkdir -p build_
        cd build_
        folly_DIR="${FOLLY_CMAKE}" \
          cmake ../
        make
        make install DESTDIR="{{OPT}}"
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FBTHRIFT_DIR: "{{OPTS_DIR}}/fbthrift-{{INSTANCE|default('-git')}}"
      FOLLY_DIR: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
      FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
      GLOG_DIR: "{{OPTS_DIR}}/glog-{{INSTANCE|default('-git')}}"
      RSOCKET_DIR: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('git')}}"
      WANGLE_DIR: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('-git')}}"
    ENV:
      FBTHRIFT_CMAKE: "${TBTHRIFT_DIR}${LIBDIR}fbthrift"
      FIZZ_CMAKE: "${FIZZ_DIR}${LIBDIR}fizz"
      FOLLY_CMAKE: "${FOLLY_DIR}${LIBDIR}folly"
      GLOG_CMAKE: "${GLOG_DIR}${LIBDIR}glog"
      RSOCKET_CMAKE: "${RSOCKET_DIR}${LIBDIR}rsocket"
      WANGLE_CMAKE: "${WANGLE_DIR}${LIBDIR}wangle"
      INSTALL_DIR: "{{OPT}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
