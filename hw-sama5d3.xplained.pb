---
- hosts: all
  vars_files:
  - ["private/$configset.vars", "private/{{TYPE}}.vars", "examples-private/{{TYPE}}.vars"]
  vars:
    TYPE: hw-sama5d3
    INSTANCE: main

    arch: ARM
    cc: "arm-linux-gnueabihf-"
    debarch: armhf
    kernel: linux-3.19
    kernel_url: "https://www.kernel.org/pub/linux/kernel/v3.x/{{kernel}}.tar.xz"

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
      "var/pdebuild-cross.tgz": "/srv/pdebuildx-armhf/pdebuild-cross.tgz"
    PKGS:
    - device-tree-compiler

    #BINS_RUN_BYPASS: True # install but do not run
    BINS:
    - prepare-sd.sh
    - install-sd.sh
    - part1-install-sd.sh
    - part2-install-sd.sh
    # using mainline uboot is good enough; not seeing any advantage to at91boot
    - src: build-at91boot.sh
      dest: build-at91boot-sd.sh
      repo_dir: "{{DIR}}/at91boot"
      target: sama5d3_xplainedsd_uboot_defconfig
      output: "{{VAR}}/at91boot-sd-nand"
      run: True
    - src: build-at91boot.sh
      dest: build-at91boot-nand.sh
      repo_dir: "{{DIR}}/at91boot"
      target: sama5d3_xplainednf_uboot_defconfig
      output: "{{VAR}}/at91boot-nand"
    - src: ../build-uboot.sh
      dest: build-uboot-sd.sh
      repo_dir: "{{DIR}}/u-boot"
      target: sama5d3_xplained_mmc_config
      output: "{{VAR}}/u-boot-sd"
      run: True
    - src: ../build-uboot.sh
      dest: build-uboot-nand.sh
      repo_dir: "{{DIR}}/u-boot"
      target: sama5d3_xplained_nandflash_config
      output: "{{VAR}}/u-boot-nand"
      run: True
    - src: ../build-deb-kernel.sh
      dest: build-deb-kernel.sh
      repo_dir: "{{kernel_dir}}"
      output: "{{VAR}}/"
      #config_target: "sama5_defconfig"
      defconfig: "{{VAR}}/kernel-defconfig"
      kernel_target: 'deb-pkg'
      after_kernel: 'cp arch/arm/boot/dts/at91-sama5d3_xplained.dtb debian/tmp/boot/vmlinuz* "${OUTPUT_DIR}/"'
      localverion: xplain
      run: True

  tasks:
  - include: tasks/compfuzor.includes type=opt


  # get kernel
  #- get_url: url="{{kernel_url}}" dest="{{kernel_dir}}.tar.xz"
  #- file: path="{{kernel_dir}}" state=directory
  #- shell: chdir="{{kernel_dir}}" tar xfJ "{{kernel_dir}}.tar.xz" --strip-components=1

  # symlink extras
  # TODO: u-boot defaults: at91-sama5d3_xplained.dtb zImage
  - include: tasks/find_latest.tasks find="{{SRCS_DIR}}/linux-*xplain_armhf.deb"
  - file: src="{{latest}}" dest="{{VAR}}/{{latest|basename}}" state=link
  - include: tasks/find_latest.tasks find="{{VAR}}/vmlinuz-3.*"
  - file: src="{{latest}}" dest="{{VAR}}/vmlinuz-latest" state=link
