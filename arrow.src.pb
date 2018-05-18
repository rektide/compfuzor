- hosts: all
  vars:
    TYPE: arrow
    INSTANCE: git
    REPO: https://github.com/apache/arrow
    PKGS:
    - libboost-dev
    - libboost-filesystem-dev
    - libboost-system-dev
    - libgtest-dev
    - libjemalloc-dev
    - libbrotli-dev
    - liblz4-dev
    - libsnappy-dev
    - zlib1g-dev
    - libzstd-dev
    - libgrpc-dev
    features:
    - plasma
    - jemalloc
    - with_grpc
    - use_sse4
    - extra_error_context
    ENV:
      CMAKE_FLAGS: "-DARROW_{{features|map('upper')|join('=on -DARROW_')}}=on"
    BINS:
    - name: build.sh
      basedir: True
      run: True
      content: |
        mkdir -p release-cpp
        cd release-cpp
        cmake ../cpp $CMAKE_FLAGS
        make
  tasks:
  - include: tasks/compfuzor.includes type=src
