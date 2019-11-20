---
- hosts: all
  vars:
    TYPE: watchman
    INSTANCE: git
    REPO: https://github.com/facebook/watchman
    OPT_DIR: True
    BINS:
    - name: build.sh
      run: True
      content: |
        #./autogen.sh
        mkdir -f build
        cd build
        FBThrift_dir="${FBTHRIFT_CMAKE}" \
          fizz_CMAKE="${FIZZ_CMAKE}" \
          rsocket_CMAKE="${RSOCKET_CMAKE}" \
          wangle_CMAKE="${WANGLE_CMAKE}" \
          yarpl_CMAKE="${RSOCKET_CMAKE}" \
          cmake ..
        make
        make install DESTDIR="{{OPT}}"
    ENV:
      LIBDIR: "/usr/local/lib/cmake/"
      FBTHRIFT_DIR: True
      FBTHRIFT_CMAKE: "${TBTHRIFT_DIR}${LIBDIR}fbthrift"
      FIZZ_DIR: True
      FIZZ_DIR: "${FIZZ_DIR}${LIBDIR}fizz"
      RSOCKET_DIR: True
      RSOCKET_CMAKE: "${RSOCKET_DIR}${LIBDIR}rsocket"
      WANGLE_DIR: True
      WANGLE_CMAKE: "${WANGLE_DIR}${LIBDIR}wangle"
      INSTALL_DIR: "{{OPT}}"
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
    FBTHRIFT_DIR: "{{OPTS_DIR}}/fbthrift-{{INSTANCE|default('-git')}}"
    FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
    WANGLE_DIR: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('-git')}}"
    RSOCKET_DIR: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('git')}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
