---
- hosts: all
  vars:
    GET_URL: "https://sdk.lunarg.com/sdk/download/{{version}}/linux/vulkansdk-linux-{{arch}}-{{version}}.tar.xz"
    PKGS:
      - libglm-dev
      - cmake
      - libxcb-dri3-0
      - libxcb-present0
      - libpciaccess0
      - libpng-dev
      - libxcb-keysyms1-dev
      - libxcb-dri3-dev
      - libx11-dev
      - g++
      - gcc 
      - libmirclient-dev
      - libwayland-dev
      - libxrandr-dev
      - libxcb-randr0-dev
      - libxcb-ewmh-dev
      - git
      - python3
      - bison
      - libx11-xcb-dev
      - liblz4-dev
      - libzstd-dev
      - python3-distutils
      - ocaml-core
      - ninja-build
      - pkg-config
      - libxml2-dev
      - wayland-protocols
      - qtcreator
      - qtbase5-dev
      - qt5-qmake
      - qtbase5-dev-tools
      - qt6-base-dev
    version: 1.4.335.0
    arch: x86_64
    ENV:
      arch: "{{arch}}"
      version: "{{version}}"
      VULKAN_SDK: "{{DIR}}"
      #PATH: "{{DIR}}/bin"
      #LD_LIBRARY_PATH: "{{DIR}}/lib"
      #VK_LAYER_PATH: "{{DIR}}/share/vulkan/explicit_layer.d"
      #VK_ADD_LAYER_PATH: "{{DIR}}/share/vulkan/explicit_layer.d"
      #PKG_CONFIG_PATH: "{{DIR}}/lib/pkgconfig/"
    BINS:
      - name: build.sh
        content: |
          tar -xvjf "{{SRC}}/vulkansdk-linux-{{arch}}-{{version}}.tar.xz"
  tasks:
    - import_tasks: tasks/compfuzor.includes
