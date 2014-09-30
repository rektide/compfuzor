---
- hosts: all
  gather_facts: False
  vars:
    TYPE: openzwave
    INSTANCE: git
    TGZ: http://openzwave.com/downloads/openzwave-1.0.791.tar.gz
    OPT_DIR: True
    PKGS:
    - libudev-dev
    BINS:
    - name: build-openzwave.sh
      run: true
  tasks:
  - include: tasks/compfuzor.includes type=src
