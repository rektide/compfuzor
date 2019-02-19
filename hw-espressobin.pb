---
- hosts: all
  vars:
    TYPE: hw-espressobin
    INSTANCE: main
    REPOS:
    - repo: git://git.denx.de/u-boot.git
      dest: uboot
      reference: uboot-git
    BINS:
    - name: build.sh
      exec: |
        echo try this
  tasks:
  - include: tasks/compfuzor.includes type=src
