---
- hosts: all
  vars_files:
  - ["private/$configset.vars", "private/{{TYPE}}.vars", "examples-private/{{TYPE}}.vars"]
  vars:
    TYPE: hw-sama5d3
    INSTANCE: main

    REPOS:
      at91boot: git://github.com/linux4sam/at91bootstrap.git
      uboot: git://git.denx.de/u-boot.git
    GIT_ACCEPT: True
    uboot_patch: "https://raw.github.com/eewiki/u-boot-patches/master/v2014.04/0001-sama5d3_xplained-uEnv.txt-bootz-n-fixes.patch"

    VAR_FILES:
    - uEnv.txt
    - kernel-defconfig
    - uEnv.txt
    - setenv.txt
    LINKS:
      "{{VAR}}/pdebuild-cross.tgz": "/srv/pdebuildx-armhf/pdebuild-cross.tgz"
      "{{REPO_DIR}}/linux": "/usr/src/linux"
    PKGS:
    - device-tree-compiler

    revision: 1.0
    localversion: ''
    cc: "{{CROSS_COMPILE}}"
    debarch: "{{KBUILD_DEBARCH}}"

    ARCH: "arm"
    BOARD: at91-sama5d3_xplained
    CROSS_COMPILE: "arm-linux-gnueabihf-"
    CONCURRENCY_LEVEL: '$(nproc)'
    OUTPUT_DIR: "{{VAR}}"
    LINUX_DIR: "{{REPO_DIR}}/linux"
    LINUX_DEFCONFIG: "{{VAR}}/kernel-defconfig"
    LINUX_PARAM_EXTRA: ""
    KBUILD_DEBARCH: "armhf"
    KDEB_PKGVERSION: "{{revision}}{{ '-' + localversion if localversion|default(False) else '' }}"
    REPREPRO_DISTRO: main
    IMAGE: "{{VAR}}/pdebuild-cross.tgz"

    ENV:
    - var
    - bins_dir
    - image
    - arch
    - cross_compile
    - concurrency_level
    - output_dir
    - linux_dir
    - linux_defconfig
    - linux_param_extra
    - linux_target
    - linux_revision
    - kbuild_debarch
    - kdeb_pkgversion
    - reprepro_distro
    - uboot_dir
    - at91boot_dir

    #BINS_RUN_BYPASS: True # install but do not run
    # using mainline uboot is good enough; not seeing any advantage to at91boot
    BINS:
    - prepare-sd.sh
    - install-sd.sh
    - part1-install-sd.sh
    - part2-install-sd.sh
    - collect-compiled.sh
    - build-dtb.sh
    - src: build-at91boot.sh
      dest: build-at91boot-sd.sh
      target: sama5d3_xplainedsd_uboot_defconfig
    - src: build-at91boot.sh
      dest: build-at91boot-nand.sh
      target: sama5d3_xplainednf_uboot_defconfig
    - src: ../build-uboot.sh
      dest: build-uboot-sd.sh
      target: sama5d3_xplained_mmc_config
      flavor: -sd
    - src: ../build-uboot.sh
      dest: build-uboot-nand.sh
      target: sama5d3_xplained_nandflash_config
      flavor: -nand
    - src: ../build-deb-kernel.sh
      dest: build-deb-kernel.sh
      #config_target: "sama5_defconfig"
      after_kernel: 'cp arch/arm/boot/dts/at91-sama5d3_xplained.dtb debian/tmp/boot/vmlinuz* "$OUTPUT_DIR/"; (linux_dir=$(pwd); ln -sf $(basename $(ls $linux_dir/debian/tmp/boot/vmlinuz*)) vmlinuz-latest)'

  tasks:
  - include: tasks/compfuzor.includes type=srv


  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  #- include: tasks/find_latest.tasks find="{{SRCS_DIR}}/linux-*xplain_armhf.deb"
  #- file: src="{{latest}}" dest="{{VAR}}/{{latest|basename}}" state=link
  #- include: tasks/find_latest.tasks find="{{VAR}}/vmlinuz-3.*"
  #- file: src="{{latest}}" dest="{{VAR}}/vmlinuz-latest" state=link
