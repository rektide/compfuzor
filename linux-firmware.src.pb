---
- hosts: all
  vars:
    TYPE: linux-firmware
    INSTANCE: git
    REPO: https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
  tasks:
    - include: tasks/compfuzor.includes type=src
