---
- hosts: all
  vars:
    TYPE: eden
    INSTANCE: git
    REPO: https://git.eden-emu.dev/eden-emu/eden.git
    BINS:
      - name: build.sh
        content: |
          mkdir -p build
          cd build
          #cmake .. -GNinja -DCMAKE_C_COMPILER=gcc-11 -DCMAKE_CXX_COMPILER=g++-11
          cmake .. -GNinja -DYUZU_USE_QT_WEB_ENGINE=ON -DYUZU_USE_EXTERNAL_SDL2=OFF
    PKGS:
      - autoconf
      - cmake
      - g++
      - gcc
      - git
      - glslang-tools
      - libasound2-dev
      - libboost-context-dev
      - libglu1-mesa-dev
      - libhidapi-dev
      - libpulse-dev
      - libtool
      - libudev-dev
      - libxcb-icccm4
      - libxcb-image0
      - libxcb-keysyms1
      - libxcb-render-util0
      - libxcb-xinerama0
      - libxcb-xkb1
      - libxext-dev
      - libxkbcommon-x11-0
      - mesa-common-dev
      - nasm
      - ninja-build
      - qt6-base-private-dev
      - libmbedtls-dev
      - catch2
      - libfmt-dev
      - liblz4-dev
      - nlohmann-json3-dev
      - libzstd-dev
      - libssl-dev
      - libavfilter-dev
      - libavcodec-dev
      - libswscale-dev
      - pkg-config
      - zlib1g-dev
      - libsdl2-compat-dev
      - libopus-dev
      - libenet-dev
      - libcubeb-dev
      - qt6-webengine-private-dev
      - qt6-wayland-private-dev
      - libgl1-mesa-dev
      - libglx-dev
      - vulkan-validationlayers
      - vulkan-utility-libraries-dev
      - libzycore-dev
      - libzydis-dev
      - libglfw3-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes


