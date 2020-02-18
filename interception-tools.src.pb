---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: git
    REPO: https://gitlab.com/interception/linux/tools
    OPT_DIR: true
    PKGS:
    - libevdev-dev
    - libyaml-cpp-dev
    - libudev-dev
    BINS:
    - name: build.sh
      exec: |
        mkdir -p build
        cd build
        cmake -DCMAKE_INSTALL_PREFIX={{OPTS_DIR}} ..
        make
        #make install
  tasks:
  - include: tasks/compfuzor.includes type=src
