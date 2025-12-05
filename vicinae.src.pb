---
- hosts: all
  vars:
    TYPE: vicinae
    INSTANCE: git
    REPO: https://github.com/vicinaehq/vicinae
    TOOL_VERSIONS:
      nodejs: True
    PKGS:
      - build-essential
      - cmake
      - ninja-build
      - qt6-base-dev
      - qt6-svg-dev
      - qt6-wayland-dev
      - libqt6svg6
      - libprotobuf-dev 
      - cmark-gfm
      - libcmark-gfm-dev
      - libcmark-gfm-extensions-dev
      - layer-shell-qt
      - liblayershellqtinterface-dev
      - libqalculate-dev
      - libminizip-dev
      - libabsl-dev
      - zlib1g-dev
      - qtkeychain-qt6-dev
      - librapidfuzz-cpp-dev
    BINS:
      - name: build.sh
        content: |
          mkdir -p build
          cmake -G Ninja .. \
            -DLTO=ON
            -DCMAKE_BUILD_TYPE=Release \
            -DVICINAE_PROVENANCE=compfuzor \
            -B build
          cmake --build build
          #make release
          #make host-optimized
  tasks:
    - import_tasks: tasks/compfuzor.includes
