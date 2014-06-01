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
    at91boot_repo: git://github.com/linux4sam/at91bootstrap.git
    uboot_repo: git://git.denx.de/u-boot.git
    uboot_patch: "https://raw.github.com/eewiki/u-boot-patches/master/v2014.04/0001-sama5d3_xplained-uEnv.txt-bootz-n-fixes.patch"

    BUILDERS:
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-sd-uboot.sh"
      source_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
      target: sama5d3_xplainedsd_uboot_defconfig
      bins: "{{DIR}}/bin"
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-nand-uboot.sh"
      source_dir: "{{SRCS_DIR}}/at91boot-{{NAME}}"
      target: sama5d3_xplainednf_uboot_defconfig
      bins: "{{DIR}}/bin"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-sd.sh"
      source_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_mmc_config
      bin: "{{DIR}}/bin/at91boot-u-boot-sd.bin"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-nand.sh"
      source_dir: "{{SRCS_DIR}}/u-boot-{{NAME}}"
      target: sama5d3_xplained_nandflash_config
      bin: "{{DIR}}/bin/at91boot-u-boot-nand.bin"
    - template: files/build-deb-kernel.sh
      builder: "{{DIR}}/build-deb-kernel.sh"
      source_dir: "{{SRCS_DIR}}/{{kernel}}"
      config_target: "sama5_defconfig"
      bin: "{{DIR}}/bin/linux.deb"
      defconfig: "{{DIR}}/kernel-deconfig"
      debarch: "armhf"

  tasks:
  - include: tasks/compfuzor.includes type=opt

  - get_url: url="{{linaro_url}}" dest="{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - file: path=/opt/{{linaro_simple}} state=directory
  - shell: chdir=/opt/{{linaro_simple}} tar xfJ "{{SRCS_DIR}}/{{linaro_simple}}.tar.xz" --strip-components=1

  - get_url: url="{{kernel_url}}" dest="{{SRCS_DIR}}/{{kernel}}.tar.xz"
  - file: path="{{SRCS_DIR}}/{{kernel}}" state=directory
  - shell: chdir="{{SRCS_DIR}}/{{kernel}}" tar xfJ "{{SRCS_DIR}}/{{kernel}}.tar.xz" --strip-components=1
  - copy: src=files/sama5d3-xplained/defconfig dest="{{DIR}}/kernel-defconfig"

  - git: dest="{{SRCS_DIR}}/at91boot-{{NAME}}" repo="{{at91boot_repo}}"
  - git: dest="{{SRCS_DIR}}/u-boot-{{NAME}}" repo="{{uboot_repo}}"

  - file: path="{{DIR}}/bin" state=directory
  - template: src="{{item.template}}" dest="{{item.builder}}" mode="0777"
    with_items: BUILDERS
  - shell: chdir="{{DIR}}" "{{item.builder}}"
    with_items: BUILDERS

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
