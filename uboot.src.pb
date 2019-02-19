---
- hosts: all
  vars:
    TYPE: uboot
    INSTANCE: git
    REPO: git://git.denx.de/u-boot.git
  tasks:
  - include: tasks/compfuzor.includes type=src
