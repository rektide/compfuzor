---
- hosts: all
  vars:
    REPO: https://github.com/milvus-io/milvus
    GO: True
    TOOL_VERSIONS:
      python: 3.11
      uv: latest
    #PYTHON: True
    PIP:
      - conan
    PKGS:
      - wget
      - curl
      - ca-certificates
      - gnupg2
      - g++
      - gcc
      - gfortran
      - git
      - make
      - ccache
      - libssl-dev
      - zlib1g-dev
      - zip
      - unzip
      #- clang-format-12
      #- clang-tidy-12
      - lcov
      - libtool
      - m4
      - autoconf
      - automake
      - python3
      - python3-pip
      - pkg-config
      - uuid-dev
      - libaio-dev
      - libopenblas-dev
      - libgoogle-perftools-dev
      - libjemalloc-dev
      - librocksdb-dev
      - librdkafka-dev
    ETC_FILES:
      - name: mise.toml
        content: |
          [tools]
          python = "3.11"
          uv = "latest"
          
          [settings]
          python.uv_venv_auto = true
          
          [env]
          _.python.venv = ".venv"
    BINS:
      - name: build.sh
        generatedAt: early
        content: |
          # TODO: ugh so just realizing build scripts don't run mise yikes

          # because we're using tools that still worry about GCC<5 compatibility i guess? wth
          # and definitely dont support gcc-15
          conan profile update settings.compiler.libcxx=libstdc++11 default
          make milvus
  tasks:
    - import_tasks: tasks/compfuzor.includes
