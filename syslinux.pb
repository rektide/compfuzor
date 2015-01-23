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
    VAR_FILES:
    - syslinux.cfg
    BINS:
    - mount-partitions
    - install-kernel
    - install-syslinux
    device: /dev/sdb
    fat: 1
    linux: 2
    append: "root=/dev/sda2"
    image: "vmlinuz"
  tasks:
  - include: tasks/compfuzor.includes
