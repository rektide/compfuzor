---
- hosts: all
  vars:
    TYPE: syslinux
    INSTANCE: main
    PKGS:
    - syslinux-utils
    - syslinux-common
    - syslinux
    - isolinux
    - extlinux
    - mbr
    ETC_FILES:
    - syslinux.cfg
    RUN_DIRS:
    - fat
    - linux
    LIB: /usr/lib/syslinux
    BINS:
    - mount-partitions
    - install-kernel
    - install-syslinux
    - install-gpt-syslinux
    ENV:
      syslinux_dev: /dev/sdb
      syslinux_dev_fat: '{{ "${SYSLINUX_DEV}" if (fat ~ "")|first != "/" and (fat ~ "")|first != "~" else ""}}{{fat}}'
      syslinux_dev_linux: '{{"${SYSLINUX_DEV}" if (linux ~ "")|first != "/" and (linux ~ "")|first != "~" else ""}}{{linux}}'
      syslinux_dev_bios: '{{"${SYSLINUX_DEV}" if (linux ~ "")|first != "/" and (linux ~ "")|first != "~" else ""}}{{bios}}'
      syslinux_mnt_fat: '{{RUN}}/fat'
      syslinux_mnt_linux: '{{RUN}}/linux'
    device: /dev/sdb
    linux: 1
    fat: 2
    bios: 3
    root: /dev/sdb1
    append: ""
    image: "vmlinuz"
  tasks:
  - include: tasks/compfuzor.includes
