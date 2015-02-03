---
- hosts: all
  vars:
    TYPE: hw-ubi
    INSTANCE: "{{board}}"

    arch: ARM
    board: "kirkwood-iconnect"
    board_dts: "{{board}}"
    board_dts_src: "{{DIR}}/linux/arch/arm/boot/dts/{{board_dts}}"
    board_uboot: "iconnect"
    linux_dir: "{{SRCS_DIR}}/linux"
    cc: "arm-linux-gnueabi-"
    #cc_uboot: "arm-linux-gnueabi-"
    GIT_ACCEPT: true
    DIST: "{{VAR|default()}}/dist"

    FILES:
    - README.md
    VAR_DIR: True
    ETC_DIRS:
    - uboot
    - dts
    - openocd
    ETC_FILES:
    - uboot.its
    - ubi.cfg
    - openocd/openocd-{{board}}.board.cfg
    - openocd/openocd-{{board}}.cfg
    - uboot/{{board_uboot}}.h
    - dts/{{board_dts}}.dts
    
    BINS:
    - extract-image
    - build-uboot
    - build-dtb
    #- build-itb # uboot recommended but i dig that funkiness, bootz
    #- build-uimage # legacy uboot
    - build-ubifs
    - build-ubi
    - split-ubi
    - install-dtb
    - start-openocd
    - install-uboot
    - src: ../build-deb-kernel.sh
      dest: build-deb-kernel.sh
      arch: arm
      debarch: armel
      after_kernel: 'cp arch/arm/boot/dts/kirkwood-iconnect.dtb debian/tmp/boot/vmlinuz* "${OUTPUT_DIR}/"'

    REPOS:
      uboot: git://git.denx.de/u-boot.git
    DIRS:
    - "{{DIST}}"
    - "/var/tftpd"
    LINKS:
      "pdebuild-cross.tgz": "{{SRVS_DIR}}/pdebuildx-armel/pdebuild-cross.tgz"
      "linux": "{{linux_dir}}"
      "var/{{board_dts}}.dts": "{{board_dts_src}}.dts"
      "etc/openocd/openocd.cfg": "etc/openocd/openocd-{{board}}.cfg"
      "etc/openocd/openocd.board.cfg": "etc/openocd/openocd-{{board}}.board.cfg"
      "/var/tftpd/{{NAME}}": "{{VAR}}"
    #PKGS:
    #- device-tree-compiler # junky junk junk, doesn't work with kernel dts
    #- mtd-utils # ubi tools
    #- tftpd-hpa
  tasks:
  - include: tasks/compfuzor.includes type=srv

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  #- include: tasks/find_latest.tasks find="{{VAR}}/vmlinuz-3.*"
  #- file: src="{{latest}}" dest="{{VAR}}/vmlinuz-latest" state=link
