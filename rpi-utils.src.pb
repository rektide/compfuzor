---
- hosts: all
  vars:
    TYPE: rpi-utils
    INSTANCE: git
    REPO: https://github.com/raspberrypi/utils
    PKGS:
      - libfdt-dev
    BINS:
      - name: build.sh
        exec: |
          cd dtmerge
          time cmake .
          time make
      - name: install.sh
        exec: |
          make install
  tasks:
    - include: tasks/compfuzor.includes type=src

