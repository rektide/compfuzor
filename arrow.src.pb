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
      FLAGS: "-DARRROW_{{features|map(upper)|join('=on -DARRROW_')}}=on"
    BINS:
    - name: build.sh
      basedir: True
      run: True
      content: |
        mkdir release
        cd release
        cmake ..
        make $FLAGS
  tasks:
  - include: tasks/compfuzor.includes type=src
