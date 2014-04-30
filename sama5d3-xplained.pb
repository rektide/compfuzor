---
- hosts: all
  vars:
    TYPE: sama5d3-xplained
    INSTANCE: main

    linaro: gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux
    linaro_url: "https://releases.linaro.org/14.04/components/toolchain/binaries/{{linaro}}.tar.xz"
    linaro_simple: armhf-14.04
    cc: "/opt/{{linaro_simple}}/bin/arm-linux-gnueabihf-"

    at91boot_repo: git://github.com/linux4sam/at91bootstrap.git
    at91boot_target: sama5d3_xplainednf_uboot_defconfig
    
    uboot_repo: git://git.denx.de/u-boot.git
    uboot_patch: "https://raw.github.com/eewiki/u-boot-patches/master/v2014.04/0001-sama5d3_xplained-uEnv.txt-bootz-n-fixes.patch"

  tasks:
  - include: tasks/compfuzor.includes type=opt

  # TODO: decouple from this here.
  - get_url: url="{{linaro_url}}" dest="{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - file: path="/opt/{{linaro}}" state=absent
  - file: path="/opt/{{linaro_simple}}" state=absent
  - shell: chdir=/opt tar xf "{{SRCS_DIR}}/{{linaro_simple}}.tar.xz"
  - shell: mv "/opt/{{linaro}}" "/opt/{{linaro_simple}}"

  - git: dest="{{SRC}}-at91boot" repo="{{at91boot_repo}}"
  # 
  - shell: chdir="{{SRC}}-at91boot" make mrproper
  - shell: chdir="{{SRC}}-at91boot" make sama5d3_xplainednf_uboot_defconfig
  - shell: chdir="{{SRC}}-at91boot" make ARCH=arm CROSS_COMPILE="{{cc}}"
  - shell: cp -au "{{SRC}}-at91boot/binaries/"* "{{DIR}}/"
  - shell: chdir="{{SRC}}-at91boot" make mrproper
  - shell: chdir="{{SRC}}-at91boot" make sama5d3_xplainedsd_uboot_defconfig
  - shell: chdir="{{SRC}}-at91boot" make ARCH=arm CROSS_COMPILE="{{cc}}"
  - shell: cp -au "{{SRC}}-at91boot/binaries/"* "{{DIR}}/"
  - shell: chdir="{{SRC}}-at91boot" make ARCH=arm CROSS_COMPILE="{{cc}}" mrproper

  - git: dest="{{SRC}}-uboot" repo="{{uboot_repo}}"
  - get_url: url="{{uboot_patch}}" dest="{{SRCS_DIR}}/{{NAME}}-uboot.patch"
  - shell: chdir="{{SRC}}-uboot" patch -p1 < ../{{NAME}}-uboot.patch
  # mmc envs
  - shell: chdir="{{SRC}}-uboot" make distclean
  - shell: chdir="{{SRC}}-uboot" make sama5d3_xplained_mmc_config
  - shell: chdir="{{SRC}}-uboot" make ARCH=arm CROSS_COMPILE="{{cc}}"
  - shell: cp -au "{{SRC}}-uboot/u-boot.bin" "{{DIR}}/u-uboot.bin-mmc"
  # sd envs
  - shell: chdir="{{SRC}}-uboot" make distclean
  - shell: chdir="{{SRC}}-uboot" make sama5d3_xplained_nandflash_config
  - shell: chdir="{{SRC}}-uboot" make ARCH=arm CROSS_COMPILE="{{cc}}"
  - shell: cp -au "{{SRC}}-uboot/u-boot.bin" "{{DIR}}/u-uboot.bin-nand"
  - shell: chdir="{{SRC}}-uboot" make distclean

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
