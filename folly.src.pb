---
- hosts: all
  vars:
    REPO: https://github.com/facebook/folly
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    # Point FindLibUring.cmake (find_path/find_library) at the source-built
    # liburing under {{OPTS_DIR}}/liburing-{{INSTANCE}}, whose bundled
    # io_uring.h carries the zcrx UAPI folly HEAD needs. The Debian
    # liburing-dev package's header lacks it.
    CMAKE_ARGS:
      - "-DCMAKE_PREFIX_PATH={{OPTS_DIR}}/liburing-{{INSTANCE|default('git')}}"
    PKGS:
      # also needs liburing.src.pb
      - libaio-dev
      - libboost-all-dev
      - libclang-dev
      - libdouble-conversion-dev
      - libdwarf-dev
      - libevent-dev
      - libfast-float-dev
      - libgflags-dev
      - libgmock-dev
      - libgoogle-glog-dev
      - libgtest-dev
      - liblz4-dev
      - liblzma-dev
      - libsnappy-dev
      - libsodium-dev
      - libtool
      - libunwind-dev
      - libzstd-dev
      - ninja-build
      - zlib1g-dev
      - zstd
      # - libbz2-dev
      # - libssl-dev
      # - libiberty-dev
      # - libfmt-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
