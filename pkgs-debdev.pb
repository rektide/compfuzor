---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  tasks:
  - apt: pkg=build-essential,debhelper,fakeroot,git-buildpackage,pbuilder,devscripts,dput-ng state=$APT_INSTALL
  - apt: pkg=multistrap,pdebuild-cross,xapt,dpkg-cross state=$APT_INSTALL
  - apt: pkg=libterm-size-perl,libtimedate-perl,curl,wget,dctrl-tools,gnupg,libdistro-info-perl,libjson-perl,libparse-debcontrol-perl,patch,patchutils,python-debian,sensible-utils,strace,unzip,xz-utils,debian-keyring,equivs
