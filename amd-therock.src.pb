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
      - name: build.sh
        content: |
          # TODO:
          # - non-recursive checkout
          python3 ./build_tools/fetch_sources.py
          cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx1201
          cmake --build build
  tasks:
    - import_tasks: tasks/compfuzor.includes
