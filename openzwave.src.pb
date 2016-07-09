---
- hosts: all
  gather_facts: False
  vars:
    TYPE: openzwave
    INSTANCE: git
    REPO: https://github.com/OpenZWave/open-zwave/
    OPT_DIR: True
    PKGS:
    - libudev-dev
    BINS:
    - name: build-openzwave.sh
      run: true
  tasks:
  - include: tasks/compfuzor.includes type=src
