---
- hosts: all
  vars:
    TYPE: uboot
    INSTANCE: "{{board}}"
    REPO: git://git.denx.de/u-boot.git
    BINS:
    - name: build.sh
      content: |
        [ -n "$BOARD" ] && make "$BOARD_defconfig"
        make
    ENV:
      ARCH: aarch64
      BOARD: "{{board}}"
      CROSS_COMPILE: /usr/bin/arm-linux-gnueabihf-gcc-8
    PKGS:
    - gcc-aarch64-linux-gnu
    - binutils-aarch64-linux-gnu
    #- gcc-arm-linux-gnueabihf
    #- binutils-arm-linux-gnueabihf
    board: espressobin
  tasks:
  - include: tasks/compfuzor.includes type=src
