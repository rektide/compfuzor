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
      basedir: west
      exec:
        python3 setup.py bdist_wheel
    - name: build-zephyr.sh
      basedir: zephyr
      exec:
        python3 setup.py bdist_wheel
    - name: build.sh
      exec:
        ./bin/build-west.sh
        ./bin/build-zephyr.sh
    PKGS:
    - python3-wheel
    - python3-setuptools
  tasks:
  - include: tasks/compfuzor.includes type=src
