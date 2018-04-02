---
- hosts: all
  vars:
    TYPE: bldc-tool
    INSTANCE: git
    REPO: https://github.com/vedderb/bldc-tool
    PKGS:
    - qt5-qmake
    - qtbase5-dev
    - libudev-dev
    - libqt5serialport5-dev
    BINS:
    - name: build.sh
      content: |
        qmake -qt=qt5
        make clean
        make
  tasks:
  - include: tasks/compfuzor.includes type=src
