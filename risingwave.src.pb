---
- hosts: all
  vars:
    TYPE: risingwave
    INSTANCE: git
    REPO: https://github.com/risingwavelabs/risingwave
    RUST: True
    RUST_BIN: risingwave
    RUST_PKG: risingwave_cmd_all
    RUST_FEATURES: rw-static-link
    PKGS:
      - build-essential
      - cmake
      - protobuf-compiler
      - pkg-config
      - libssl-dev
      - libsasl2-dev
      - libblas-dev
      - liblapack-dev
      - libomp-dev
      - lld
      - parallel
      - curl
      - postgresql-client
      - tmux
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
