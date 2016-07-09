---
- hosts: all
  vars:
    TYPE: sbuild-chroot
    INSTANCE: main
    BINS:
    - build
    PKGS:
    - buildd
    - sbuild
    PKGS_BYPASS: True
    CACHE_DIR: True

    ENV:
      SUITE: "{{ APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION,true) }}"
      TARGET: "{{ CACHE }}"
      DEBIAN_MIRROR_URI: "{{ APT_MIRROR|default(APT_DEFAULT_MIRROR,true) }}"

      ARCH: True
      NATIVE_ARCH: True
      CHROOT_SUFFIX:
      FOREIGN: "{{ True if NATIVE_ARCH != ARCH else 'MAGIC_NONE_COMPFUZOR' }}"
      RESOLVE:
      KEEP:
      DEBOOTSTRAP:
      INCLUDE:
      EXCLUDE:
      COMPONENTS:
      - main
      - contrib
      - non-free
      KEYRING:
 
  tasks:
  - include: tasks/compfuzor.includes type=srv
