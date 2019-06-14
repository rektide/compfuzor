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
      exec: python3 setup.py bdist_wheel
    - name: install-west.sh
      basedir: west
      exec: pip3 install -U $(ls --sort=time dist/west-*-py3-none-any.whl | head -n1)
    - name: build-zephyr.sh
      basedir: zephyr
      exec: echo build zephyr pls
    - name: build.sh
      exec:
        ./bin/build-west.sh
        ./bin/install-west.sh
        ./bin/build-zephyr.sh
    PKGS:
    - python3-wheel
    - python3-setuptools
    - python3-tk
    - ninja-build
    - gperf
    - ccache
  tasks:
  - include: tasks/compfuzor.includes type=src
