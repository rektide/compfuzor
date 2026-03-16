---
- hosts: all
  vars:
    REPO: https://github.com/facebook/folly
    CMAKE: True
    BUILD_DIR: "_build"
    CMAKE_INSTALL: True
    BINS:
    - name: build.sh
      run: True
      #generatedAt: False
      #baseDir: repo
      #content: |
      #  python ./build/fbcode_builder/getdeps.py --allow-system-packages build
    #OPT_DIR: true
    PKGS:
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
