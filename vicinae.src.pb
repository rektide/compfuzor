---
- hosts: all
  vars:
    TYPE: vicinae
    INSTANCE: git
    REPO: https://github.com/vicinaehq/vicinae
    TOOL_VERSIONS:
      node: "{{NODE_VERSION}}"
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
          cd build
          cmake -G Ninja .. \
            -DLTO=ON
          #make release
          make host-optimized
  tasks:
    - import_tasks: tasks/compfuzor.includes
