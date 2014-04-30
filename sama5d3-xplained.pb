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

    at91boot_repo: git://github.com/linux4sam/at91bootstrap.git
    uboot_repo: git://git.denx.de/u-boot.git
    uboot_patch: "https://raw.github.com/eewiki/u-boot-patches/master/v2014.04/0001-sama5d3_xplained-uEnv.txt-bootz-n-fixes.patch"

    BUILDERS:
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-sd-uboot.sh"
      target: sama5d3_xplainedsd_uboot_defconfig
      source_dir: "{{SRCS_DIR}}/at91boot"
      bins: "{{DIR}}/bin"
    - template: files/build-at91boot.sh
      builder: "{{DIR}}/build-at91boot-nand-uboot.sh"
      source_dir: "{{SRCS_DIR}}/at91boot"
      target: sama5d3_xplainednf_uboot_defconfig
      bins: "{{DIR}}/bin"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-sd.sh"
      source_dir: "{{SRCS_DIR}}/u-boot"
      target: sama5d3_xplained_mmc_config
      bin: "{{DIR}}/bin/u-boot-sd.bin"
    - template: files/build-uboot.sh
      builder: "{{DIR}}/build-uboot-nand.sh"
      source_dir: "{{SRCS_DIR}}/u-boot"
      target: sama5d3_xplained_nandflash_config
      bin: "{{DIR}}/bin/u-boot-nand.bin"

  tasks:
  - include: tasks/compfuzor.includes type=opt

  # TODO: decouple this from here.
  - get_url: url="{{linaro_url}}" dest="{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - file: path="/opt/{{linaro}}" state=absent
  - file: path="/opt/{{linaro_simple}}" state=absent
  - shell: chdir=/opt tar xf "{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - shell: mv "/opt/{{linaro}}" "/opt/{{linaro_simple}}"

  - git: dest="{{SRCS_DIR}}/at91boot" repo="{{at91boot_repo}}"

  - git: dest="{{SRCS_DIR}}/u-boot" repo="{{uboot_repo}}"
  - get_url: url="{{uboot_patch}}" dest="{{SRCS_DIR}}/{{NAME}}-uboot.patch"
  - shell: chdir="{{SRCS_DIR}}/u-boot" patch -p1 < ../{{NAME}}-uboot.patch

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
