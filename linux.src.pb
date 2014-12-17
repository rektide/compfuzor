---
- hosts: all
  gather_facts: False
  vars:
    TYPE: linux
    INSTANCE: 3.18
    TGZ: https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.18.tar.xz
    OPTS_DIR: /usr/src
  tasks:
  - include: tasks/compfuzor.includes type=src
