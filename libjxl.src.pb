---
- hosts: all
  vars:
    TYPE: libjxl
    INSTANCE: git
    REPO: https://github.com/libjxl/libjxl
    PKGS:
      - cmake
      - pkg-config
      - libbrotli-dev
      - libgif-dev
      - libjpeg-dev
      - libopenxr-dev
      - libpng-dev
      - libwebp-dev
      - asciidoc
      - docbook-xml
      - libxml2-utils
      - libglut-dev
      # debian build stuff
      - ninja-build
      - doxygen
      - clang
      - g++
      - extra-cmake-modules
      - libgoogle-perftools-dev
    BINS:
      - name: build.sh
        exec: |
          mkdir -p build
          cd build
          cmake -DCMAKE_BUILD_TYPE=release -DBUILD_TESTING=off ..
          cmake --build . -- -j$(nproc)
      - name: install.sh
        exec: sudo cmake --install build
      - name: build-debian.sh
        exec: |
          ./ci.sh highway
          ./ci.sh jpeg-xl
    ENV:
      CC: clang
      CXX: clang++
  tasks:
    - include: tasks/compfuzor.includes type=src
