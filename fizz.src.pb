---
- hosts: all
  vars:
    TYPE: fizz
    INSTANCE: git 
    REPO: https://github.com/facebookincubator/fizz
    BINS:
    - name: build.sh
      basedir: fizz
      content: |
        mkdir -p build
        cd build
        folly_DIR="${FOLLY_CMAKE}" \
          cmake ..
        make -j $(nproc)
        make install DESTDIR=${INSTALL_DIR}
    ENV_PRIO:
      LIBDIR: "/usr/local/lib/cmake/"
      FOLLY_DIR: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
    ENV:
      FOLLY_CMAKE: "${FOLLY_DIR}${LIBDIR}folly"
      INSTALL_DIR: "{{OPT}}"
    OPT_DIR: true
    PKGS:
    - libevent-dev
    - libdouble-conversion-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libiberty-dev
    - liblz4-dev
    - liblzma-dev
    - libsnappy-dev
    - zlib1g-dev
    - libjemalloc-dev
    - libsodium-dev

  tasks:
  - include: tasks/compfuzor.includes type=src
