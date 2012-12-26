---
- hosts: all
  vars_files:
  - vars/common.vars
  tasks:
  - name: install ceph packages
    apt: pkg=ceph,btrfs-tools,ceph-fuse,libcephfs1,radosgw state=$APT_INSTALL

