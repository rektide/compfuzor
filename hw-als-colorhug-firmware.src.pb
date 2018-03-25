---
- hosts: all
  vars:
    TYPE: hw-colorhug-als-firmware
    INSTANCE: git
    REPO: https://github.com/hughski/colorhug-als-firmware
    GIT_VERSION: sensor-hid
    BINS:
    - name: build.sh
      content: make
      run: True
    PKGS:
    - libusb-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
