---
- hosts: all
  vars:
    TYPE: wasi-sdk
    INSTANCE: git
    REPO: https://github.com/WebAssembly/wasi-sdk
    CMAKE: True
    CMAKE_INSTALL: --prefix /opt/wasi-sdk
    CMAKE_BUILDS:
      - name: toolchain
        build_dir: build/toolchain
        args:
          - -DWASI_SDK_BUILD_TOOLCHAIN=ON
        build_target: build
      - name: sysroot
        build_dir: build/sysroot
        args:
          - -DCMAKE_TOOLCHAIN_FILE=build/toolchain/install/share/cmake/wasi-sdk.cmake
          - -DCMAKE_C_COMPILER_WORKS=ON
          - -DCMAKE_CXX_COMPILER_WORKS=ON
        build_target: build
    PKGS:
      - cmake
      - clang
      - ninja-build
      - python3
      - cargo
    #LINKS:
    #  /usr/local/bin/wasi-sdk-clang: /opt/wasi-sdk/bin/clang
  tasks:
    - import_tasks: tasks/compfuzor.includes
