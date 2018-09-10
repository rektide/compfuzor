- hosts: all
  vars:
    TYPE: mlnx-ofed
    INSTANCE: 4.4
    TGZ: http://www.mellanox.com/downloads/ofed/MLNX_OFED-4.4-2.0.7.0/MLNX_OFED_SRC-debian-4.4-2.0.7.0.tgz
    BINS:
    - name: build.sh
      exec: |
        sudo ./install.pl
    PKGS:
    - dpatch
    - graphviz
    - gfortran
    - libmnl-dev
    - libnuma-dev
    - libelf-dev
    - quilt
    - libnl-3-dev
    - swig
    - chrpath
    - libdb-dev
    - libnl-3-200
    - debhelper
    - libselinux1-dev
    - libcr-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
