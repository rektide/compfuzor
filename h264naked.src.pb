---
- hosts: all
  vars:
    TYPE: h264naked
    INSTANCE: git
    REPO: https://github.com/shi-yan/H264Naked
    PKGS:
      - qt5-qmake
      - qt5-qmake-bin
      - qtbase5-dev
      #- qt6-5compat-dev
  tasks:
    - include: tasks/compfuzor.includes type=src
