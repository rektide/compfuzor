---
- hosts: all
  vars:
    TYPE: h264naked
    INSTANCE: git
    REPO: https://github.com/iquadtree/H264Naked
    PKGS:
      - qbs
      - qt5-qmake
      - qt5-qmake-bin
      - qtbase5-dev
    BINS:
      - name: build.sh
        exec: qbs
      - dest: h264naked
        link: "{{VAR}}/default/install-root/usr/local/bin/H264Naked"
        global: True
  tasks:
    - include: tasks/compfuzor.includes type=src
