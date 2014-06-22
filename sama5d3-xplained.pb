---
- hosts: all
  vars:
    TYPE: sama5d3-xplained
    INSTANCE: main

    linaro: gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux
    linaro_url: "https://releases.linaro.org/14.04/components/toolchain/binaries/{{linaro}}.tar.xz"
    linaro_simple: armhf-14.04

    arch: ARM
    cc: "/opt/{{linaro_simple}}/bin/arm-linux-gnueabihf-"

    kernel: linux-3.15-rc7
    kernel_url: "https://www.kernel.org/pub/linux/kernel/v3.x/testing/{{kernel}}.tar.xz"
    kernel_dir: "{{SRCS_DIR}}/{{kernel}}"
    at91boot_repo: git://github.com/linux4sam/at91bootstrap.git
    uboot_repo: git://git.denx.de/u-boot.git
    uboot_patch: "https://raw.github.com/eewiki/u-boot-patches/master/v2014.04/0001-sama5d3_xplained-uEnv.txt-bootz-n-fixes.patch"
    pdebuild_cross: "/srv/pdebuildx-armhf/pdebuild-cross.tgz"

    VAR_FILES:
    - uEnv.txt
    - kernel-defconfig
    LINKS:
      pdebuild-cross.tgz: "{{pdebuild_cross}}"
    PKGS:
    - device-tree-compiler

    BINS_RUN_BYPASS: True
    BINS:
    #- build-dtb.sh # kernel does this
    #- prepare-image.sh # pdebuildx does this
    - prepare-sd.sh
    - install-sd.sh
    # using mainline uboot is good enough; not seeing any advantage to at91boot
    #- src: build-at91boot.sh
    #  dest: build-at91boot-sd.sh
    #  repo_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
    #  target: sama5d3_xplainedsd_uboot_defconfig
    #  output: "{{VAR}}/at91boot-sd"
    #- src: build-at91boot.sh
    #  dest: build-at91boot-nand.sh
    #  repo_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
    #  target: sama5d3_xplainednf_uboot_defconfig
    #  output: "{{VAR}}/at91boot-nand"
    - src: build-uboot.sh
      dest: build-uboot-sd.sh
      repo_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_mmc_config
      output: "{{VAR}}/u-boot-sd"
      run: True
    - src: build-uboot.sh
      dest: build-uboot-nand.sh
      repo_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_nandflash_config
      output: "{{VAR}}/u-boot-nand"
      run: True
    - src: build-deb-kernel.sh
      dest: build-deb-kernel.sh
      repo_dir: "{{kernel_dir}}"
      output: "{{VAR}}/"
      #config_target: "sama5_defconfig"
      defconfig: "{{VAR}}/kernel-defconfig"
      kernel_param: 'INSTALL_DTBS_PATH=debian/tmp/boot'
      kernel_target: 'dtbs_install deb-pkg'
      after_kernel: 'cp arch/arm/boot/dts/at91-sama5d3_xplained.dtb debian/tmp/boot/vmlinuz* "${OUTPUT_DIR}/"'
      arch: arm
      debarch: armhf
      localverion: xplain
      run: True

  tasks:
  - include: tasks/compfuzor.includes type=opt

  # get linaro
  - get_url: url="{{linaro_url}}" dest="{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - file: path=/opt/{{linaro_simple}} state=directory
  - shell: chdir=/opt/{{linaro_simple}} tar xfJ "{{SRCS_DIR}}/{{linaro_simple}}.tar.xz" --strip-components=1

  # get kernel
  - get_url: url="{{kernel_url}}" dest="{{kernel_dir}}.tar.xz"
  - file: path="{{kernel_dir}}" state=directory
  - shell: chdir="{{kernel_dir}}" tar xfJ "{{kernel_dir}}.tar.xz" --strip-components=1

  # get boot programs
  - git: dest="{{SRCS_DIR}}/at91boot-{{NAME}}" repo="{{at91boot_repo}}"
  - git: dest="{{SRCS_DIR}}/u-boot-{{NAME}}" repo="{{uboot_repo}}"

  - include: tasks/compfuzor/bins_run.tasks

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  - file: src="{{kernel_dir}}/arch/arm/boot/dts/at91-sama5d3_xplained.dtb" dest="{{VAR}}/at91-sama5d3_xplained.dtb"
  - include: tasks/find_latest.tasks find="{{SRCS_DIR}}/linux-*xplain_armhf.deb"
  - debug: msg="{{latest}} is latest"
  - file: src="{{latest}}" dest="{{VAR}}/{{latest|basename}}" state=link
