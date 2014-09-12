---
- hosts: all
  vars:
    TYPE: accelio
    INSTANCE: git
    REPO: https://github.com/accelio/accelio
    SRV_DIR: True
    CORES: 1
    PKGS:
    - libtool
    - autoconf
    - automake
    - build-essential
    - librdmacm-dev
    - libibverbs-dev
    - numactl
    - libnuma-dev
    - libaio-dev
    - ibverbs-utils
    - rdmacm-utils
    - infiniband-diags
    - perftest
    BINS:
    - name: "make-{{NAME}}"
      src: "../make-src"
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
