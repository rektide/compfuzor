---
- hosts: all
  vars:
    TYPE: amd-therock
    INSTANCE: git
    REPO: https://github.com/ROCm/TheRock
    PKGS:
      - patchelf
      # manually install cppparseheader
      #- python3-cxxheaderparser
      - python3-build
      - python3-joblib
      - python3-magic
      - python3-mako
      - python3-mesonpy
      - python3-msgpack
      - python3-pyzstd
      - python3-yaml
      - libexpat1-dev
      - libbacktrace-dev
      - libcap-dev
      - libgmp-dev
      - libdrm-dev
      - liblzma-dev
      - libmpfr-dev
      - numactl
      - libsqlite3-dev
      - sqlite3-tools
      - sqlite3
      - zlib1g-dev
    BINS:
      - name: config.sh
        content: |
          python3 ./build_tools/fetch_sources.py
          #cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx1201
          cmake -B build -GNinja . \
            -DCMAKE_BUILD_TYPE=Release \
            -DTHEROCK_AMDGPU_FAMILIES=gfx120X-all \
            -DTHEROCK_BUNDLED_EXPAT=false \
            -DTHEROCK_BUNDLED_LIBBACKTRACE=false \
            -DTHEROCK_BUNDLED_LIBCAP=false \
            -DTHEROCK_BUNDLED_GMP=false \
            -DTHEROCK_BUNDLED_LIBDRM=false \
            -DTHEROCK_BUNDLED_LIBLZMA=false \
            -DTHEROCK_BUNDLED_LIBMPFR=false \
            -DTHEROCK_BUNDLED_NCURSES=false \
            -DTHEROCK_BUNDLED_SQLITE3=false \
            -DTHEROCK_BUNDLED_ZLIB=false \
            -DTHEROCK_BUNDLED_ZSTD=false \
            -DTHEROCK_ENABLE_SYSDEPS_EXPAT=false \
            -DTHEROCK_ENABLE_SYSDEPS_GMP=false \
            -DTHEROCK_ENABLE_SYSDEPS_MPFR=false \
            -DTHEROCK_ENABLE_SYSDEPS_NCURSES=false \
            -DTHEROCK_ENABLE_CORE_HIPTESTS=false \
            -DTHEROCK_ENABLE_AQLPROFILE_TESTS=false \
            -DTHEROCK_ENABLE_CORE_RUNTIME_TESTS=false \
            -DTHEROCK_ENABLE_ROCR_DEBUG_AGENT_TESTS=false
      - name: build.sh
        content: |
          cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx120X-all
          CMAKE_BUILD_PARALLEL_LEVEL=3 cmake --build build 
      - name: install-python.sh
        content: |
          # https://github.com/ROCm/TheRock/blob/main/RELEASES.md#installing-releases-using-pip
          pip install --index-url https://rocm.nightlies.amd.com/v2/gfx120X-all/ "rocm[libraries,devel]"
          pip install --index-url https://rocm.nightlies.amd.com/v2/gfx120X-all/ torch torchaudio torchvision
      - name: perms.sh
        content: |
          sudo sudo usermod -a -G video,render $USER
  tasks:
    - import_tasks: tasks/compfuzor.includes
