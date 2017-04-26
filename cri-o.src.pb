---
- hosts: all
  vars:
    TYPE: cri-o
    REPO: https://github.com/kubernetes-incubator/cri-o
    PKGS:
    - btrfs-tools
    - libassuan-dev
    - libdevmapper-dev
    - libglib2.0-dev
    - libc6-dev
    - libgpgme11-dev
    - libgpg-error-dev
    - libseccomp-dev
    - libselinux1-dev
    - pkg-config
  tasks:
  - include: tasks/compfuzor.includes type=src
