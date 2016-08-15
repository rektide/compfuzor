---
- hosts: all
  vars:
    TYPE: libdispatch
    INSTANCE: git
    REPO: https://github.com/apple/swift-corelibs-libdispatch
    PKGS:
    - libtool
    - clang
    - systemtap-sdt-dev
    - libbsd-dev
    - libblocksruntime-dev 
    BINS:
    - name: "build-submodule.sh"
      execs:
      - cd repo
      - git submodule init
      - git submodule update
      run: True
    - name: "build.sh"
      src: "../make-src"
      run: True
    PRE_CONFIGURE: "export PATH=/usr/lib/llvm-4.0/bin:$PATH"
  tasks:
  - include: tasks/compfuzor.includes
