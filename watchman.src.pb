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
        mkdir -p build_
        cd build_
        folly_DIR="${FOLLY_CMAKE}" \
          cmake \
          -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
          ..
        make
        make install #DESTDIR="{{OPT}}"
    - name: proc-inotify.sh
      run: False
      become: true
      content: |
        # impacts how many different root dirs you can watch.
        echo 409 > /proc/sys/fs/inotify/max_user_instances
        # impacts how many dirs you can watch across all watched roots.
        echo 131072 > /proc/sys/fs/inotify/max_user_watches
        echo 65536 > /proc/sys/fs/inotify/max_queued_events 
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FBTHRIFT_DIR: "{{OPTS_DIR}}/fbthrift-{{INSTANCE|default('-git')}}"
      FIZZ_DIR: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
      FOLLY_DIR: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
      RSOCKET_DIR: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('git')}}"
      WANGLE_DIR: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('-git')}}"
    ENV:
      FBTHRIFT_CMAKE: "${TBTHRIFT_DIR}${LIBDIR}fbthrift"
      FIZZ_CMAKE: "${FIZZ_DIR}${LIBDIR}fizz"
      FOLLY_CMAKE: "${FOLLY_DIR}${LIBDIR}folly"
      RSOCKET_CMAKE: "${RSOCKET_DIR}${LIBDIR}rsocket"
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
    - libpcre2-dev
    - inotify-tools
  tasks:
  - include: tasks/compfuzor.includes type=src
