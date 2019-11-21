---
- hosts: all
  vars:
    TYPE: glog
    INSTANCE: git
    REPO: https://github.com/google/glog
    OPT_DIR: True
    BINS:
    - name: build.sh
      basedir: true
      content: |
        mkdir build_
        cd build_
        cmake ..
        make
        make install DESTDIR="{{INSTALL_DIR}}"
    ENV:
      INSTALL_DIR: "{{OPT}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
