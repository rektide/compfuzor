---
- hosts: all
  vars:
    TYPE: hw-ubifs
    INSTANCE: "{{board}}"

    arch: ARM
    board: "kirkwood-iconnect"
    board_dts: "{{board}}"
    board_uboot: "iconnect"
    cc: "arm-linux-gnueabi-"
    #cc_uboot: "arm-linux-gnueabi-"
    DIST: "{{VAR}}/dist"

    VAR_DIR: True
    ETC_FILES:
    - uboot.its
    - ubi.cfg
    - openocd_iconnect.board.cfg
    - openocd_iconnect.cfg
    
    BINS_RUN_BYPASS: True # install but do not run
    BINS:
    - extract-image
    - build-uboot
    - build-dtb
    - build-itb
    #- build-uimage # legacy uboot
    - build-ubifs
    - build-ubi
    - install-dtb

    REPOS_p:
      uboot: git://git.denx.de/u-boot.git
    DIRS:
    - "{{DIST}}"
    LINKS:
      "pdebuild-cross.tgz": "{{SRVS_DIR}}/pdebuildx-armel/pdebuild-cross.tgz"
      "linux": "{{SRCS_DIR}}/linux"
    PKGS:
    - device-tree-compiler
    - mtd-utils

  tasks:
  - include: tasks/compfuzor.includes type=srv

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  #- include: tasks/find_latest.tasks find="{{VAR}}/vmlinuz-3.*"
  #- file: src="{{latest}}" dest="{{VAR}}/vmlinuz-latest" state=link
