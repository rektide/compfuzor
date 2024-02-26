---
- hosts: all
  vars:
    TYPE: rpi-update
    INSTANCE: git
    REPO: https://github.com/raspberrypi/rpi-update
  tasks:
    - include: tasks/compfuzor.includes type=src
