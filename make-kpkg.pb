---
- hosts: all
  sudo: True
  vars_files:
  - vars/apt.vars
  tasks:
  - name: install kernel-package main deps
    apt: state=$APT_INSTALL pkg=binutils,build-essential,debianutils,gettext,make,module-init-tools,po-debconf,util-linux
  - name: install make-kpkg
    apt: state=$APT_INSTALL pkg=kernel-package,bzip2,initramfs-tools,fakeroot
  - name: install busybox extras
    apt: state=$APT_INSTALL pkg=busybox-static
