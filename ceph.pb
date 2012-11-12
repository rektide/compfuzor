---
- hosts: all
- tasks:
  - name: install ceph packages
    apt: pkg=ceph,btrfs-tools,ceph-fuse,libcephfs1,radosgw state=latest

