---
- hosts: all
  vars_files:
  - vars/common.vars
  tasks:
  - name: debdev basics
    apt: pkg=build-essential,debhelper,fakeroot,git-buildpackage,pbuilder,devscripts state=$APT_INSTALL
  - name: debdev multistrap
    apt: pkg=multistrap,pdebuild-cross,xapt,dpkg-cross state=$APT_INSTALL
  - name: debdev repo
    apt: pkg=mini-dinstall,dput state=$APT_INSTALL
