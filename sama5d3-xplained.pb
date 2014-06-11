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

    FILES:
    - uEnv.txt
    - kernel-defconfig
    SH:
    - build-dtb.sh
    - prepare-image.sh
    - prepare-sd.sh
    - install-sd.sh

    BUILDERS:
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-sd.sh"
      source_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
      target: sama5d3_xplainedsd_uboot_defconfig
      bin: "{{DIR}}/bin/at91boot-sd"
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-nand.sh"
      source_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
      target: sama5d3_xplainednf_uboot_defconfig
      bin: "{{DIR}}/bin/at91boot-nand"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-sd.sh"
      source_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_mmc_config
      bin: "{{DIR}}/bin/u-boot-sd"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-nand.sh"
      source_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_nandflash_config
      bin: "{{DIR}}/bin/u-boot-nand"
    - template: files/build-deb-kernel.sh
      builder: "{{DIR}}/build-deb-kernel.sh"
      source_dir: "{{kernel_dir}}"
      bin: "{{DIR}}/bin/linux.deb"
      config_target: "sama5_defconfig"
      defconfig: "{{DIR}}/kernel-defconfig"
      kernel_param: ''
      kernel_target: 'dtbs_install deb-pkg'
      after_kernel: 'cp arch/arm/boot/dts/at91-sama5d3_xplained.dtb "${OPT_DIR}"'
      arch: arm
      debarch: "armhf"

    PKGS:
    - device-tree-compiler

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

  # copy build items into place
  - file: path="{{DIR}}/bin" state=directory
  - template: src="files/sama5d3-xplained/{{item}}" dest="{{DIR}}/{{item}}" mode=644
    with_items: FILES
  - template: src="files/sama5d3-xplained/{{item}}" dest="{{DIR}}/{{item}}" mode=754
    with_items: SH
  - template: src="{{item.template}}" dest="{{item.builder}}" mode="0754"
    when: run|default(true) != false
    with_items: BUILDERS

  # run
  - shell: chdir="{{DIR}}" "{{item.builder}}"
    with_items: BUILDERS

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  - shell: ln -sf "{{kernel_dir}}/arch/arm/boot/dts/at91-sama5d3_xplained.dtb" "{{DIR}}/linux.dtb"
  - shell: ln -sf "{{SRCS_DIR}}/linux-*xplain_armhf.deb" "{{DIR}}"
  - shell: ln -sf "{{pdebuild_cross}}" "{{DIR}}/pdebuild-cross.tgz"

  #  branch_dest: sama5d3
  #  repo_poky: git://git.yoctoproject.org/poky
  #  repo_poky_tag: dora-10.0.1
  #  repo_oe: git://git.openembedded.org/meta-openembedded
  #  repo_oe_tag: 6572316557e742c2dc93848e4d560242bf0c3995
  #  repo_atmel: http://github.com/linux4sam/meta-atmel

  #- git: path="{{SRC}}-oe" repo="{{repo_poky}}"
  #- shell: chdir="{{SRC}}-oe" git checkout "{{repo_poky_tag}}" -b "{{branch_dest}}"
  #- git: path="{{SRC}}-oe/meta-openembedded" repo="{{repo_oe}}"
  #- shell: chdir="{{SRC}}-oe/meta-openembedded" git checkout "{{repo_oe_tag}}" -b "{{branch_dest}}"
  #- git: path="{{SRC}}-oe/meta-atmel" repo="{{repo_atmel}}"
  #- shell: chdir="{{SRC}}-oe}}" source oe-init-build-env build-atmel
