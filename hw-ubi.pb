---
- hosts: all
  vars:
    TYPE: hw-ubi
    INSTANCE: "{{board}}"

    arch: ARM
    board: "kirkwood-iconnect"
    board_dts: "{{board}}"
    board_uboot: "iconnect"
    cc: "arm-linux-gnueabi-"
    #cc_uboot: "arm-linux-gnueabi-"
    DIST: "{{VAR|default()}}/dist"

    VAR_DIR: True
    ETC_DIRS:
    - configs
    ETC_FILES:
    - uboot.its
    - ubi.cfg
    - openocd-{{board}}.board.cfg
    - openocd-{{board}}.cfg
    - configs/{{board_uboot}}.h
    
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
    - start-openocd
    - install-uboot

    REPOS_p:
      uboot: git://git.denx.de/u-boot.git
    DIRS:
    - "{{DIST}}"
    LINKS:
      "pdebuild-cross.tgz": "{{SRVS_DIR}}/pdebuildx-armel/pdebuild-cross.tgz"
      "linux": "{{SRCS_DIR}}/linux"
      "etc/openocd.cfg": "etc/openocd-{{board}}.cfg"
      "etc/openocd.board.cfg": "etc/openocd-{{board}}.board.cfg"
    PKGS:
    - device-tree-compiler
    - mtd-utils

  tasks:
  - include: tasks/compfuzor.includes type=srv

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  #- include: tasks/find_latest.tasks find="{{VAR}}/vmlinuz-3.*"
  #- file: src="{{latest}}" dest="{{VAR}}/vmlinuz-latest" state=link
