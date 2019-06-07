---
- hosts: all
  vars:
    TYPE: zephyr
    INSTANCE: git
    REPOS:
      zephyr: https://github.com/zephyrproject-rtos/zephyr
      west: https://github.com/zephyrproject-rtos/west
    BINS:
    - name: build-west.sh
      exec:
        python3 setup.py bdist_wheel
    - name: build.sh
      exec:
        ./build-west.sh
    PKGS:
    - python3-wheel
  tasks:
  - include: tasks/compfuzor.includes type=src
