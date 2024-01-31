---
- hosts: all
  vars:
    TYPE: amdctl
    INSTANCE: git
    REPO: https://github.com/kevinlekiller/amdctl
    BINS:
     - name: build.sh
       exec: |
         mkdir -p build
         cd build
         cmake -DCMAKE_INSTALL_PREFIX={{OPT}} ..
         make
         make install
  tasks:
    - include: tasks/compfuzor.includes type=src

