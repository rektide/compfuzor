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
        fizz_DIR="{FIZZ_CMAKE}" \
          folly_DIR="{FOLLY_CMAKE}" \
          rsocket_DIR="{RSOCKET_CMAKE}" \
          wangle_DIR="{WANGLE_CMAKE}" \
          yarpl_DIR="{YARPL_CMAKE}" \
          cmake .
          make
          sudo make install DESTDIR="{{OPT}}"
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
      RSOCKET_DIR: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('git')}}"
      WANGLE_DIR: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('-git')}}"
      YARPL_DIR: "{{OPTS_DIR}}/yarpl-{{INSTANCE|default('-git')}}"
    ENV:
      FIZZ_CMAKE: "${FIZZ_DIR}${LIBDIR}fizz"
      RSOCKET_CMAKE: "${RSOCKET_DIR}${LIBDIR}rsocket"
      WANGLE_CMAKE: "${WANGLE_DIR}${LIBDIR}wangle"
      YARPL_CMAKE: "${YARPL_DIR}${LIBDIR}yarpl"
      INSTALL_DIR: "{{OPT}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
