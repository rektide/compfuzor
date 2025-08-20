---
- hosts: all
  vars:
    TYPE: suyu
    INSTANCE: git
    REPO: https://git.suyu.dev/suyu/suyu
    BINS:
      - name: build.sh
        basedir: True
        content: |
          mkdir -p build
          cd build
          # -DCMAKE_C_COMPILER=gcc-11 -DCMAKE_CXX_COMPILER=g++-11
          # -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=glang++
          # -DSUYU_USE_BUNDLED_VCPKG=ON \
          cmake .. \
            -GNinja \
            -DCMAKE_CXX_FLAGS="-march=x86-64-v3" \
            -DSUYU_TESTS=OFF \
            -DSUYU_USE_DISCORD_PRESENCE=ON \
            -DSUYU_USE_BUNDLED_SDL2=OFF \
            -DSUYU_USE_EXTERNAL_SDL=OFF \
            -DSUYU_USE_EXTERNAL_FFMPEG=OFF \
            -DSUYU_USE_QT_WEB_ENGINE=ON
    PKGS:
      - autoconf
      - cmake
      - g++-11
      - gcc-11
      - git
      - glslang-tools
      - libasound2
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
      - qtbase5-dev
      - qtbase5-private-dev
      - qtwebengine5-dev
      - qtmultimedia5-dev
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
      - libenet-dev
      - librenderdoc-dev
      - libstb-dev
      - libvulkan-memory-allocator-dev
      - libusb-dev
      - libdynarmic-dev
      - libcubeb-dev
      - libdiscord-rpc-dev
      - libcpp-jwt-dev
      - libcpp-httplib-dev
      - gamemode-dev
      #- mcl # crypto library missing?
      - robin-map-dev
      - libxbyak-dev
      - libzydis-dev
      #- msan
      - libubsan1
      - libcurl4-openssl-dev
      - libedit-dev
  tasks:
    - include: tasks/compfuzor.includes type=src
