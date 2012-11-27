---
- hosts: all
  sudo: True
  tasks:
  - name: install kernel-package main deps
    apt: state=latest pkg=binutils,build-essential,debianutils,gettext,make,module-init-tools,po-debconf,util-linux
  - name: install make-kpkg
    apt: state=latest pkg=kernel-package,bzip2,initramfs-tools,fakeroot
  - name: install busybox extras
    apt: state=latest pkg=busybox-static
