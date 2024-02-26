---
- hosts: all
  vars:
    TYPE: rpi-eeprom
    INSTANCE: git
    REPO: https://github.com/raspberrypi/rpi-eeprom
    #BINS:
    #  - name: build.sh
    #    exec: |
    #      time echo hello-world
  tasks:
    - include: tasks/compfuzor.includes type=src
