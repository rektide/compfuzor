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
    BINS:
      - name: config.sh
        content: |
          python3 ./build_tools/fetch_sources.py
          #cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx1201
          cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx120X-all
      - name: build.sh
        content: |
          #cmake --build build
          # development docs have a dtodo for concurrencyyyyyyyyyyyyyyy control
          CMAKE_BUILD_PARALLEL_LEVEL=3 cmake --build build
  tasks:
    - import_tasks: tasks/compfuzor.includes
