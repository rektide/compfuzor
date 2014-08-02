---
- hosts: all
  vars:
    TYPE: ceph
    APT_KEY_URL: 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc'
    APT_REPO: 'http://ceph.com/debian-firefly/'
    APT_DISTRIBUTION: wheezy
    PKGSET: CEPH
  tasks:
  - include: tasks/compfuzor.includes
