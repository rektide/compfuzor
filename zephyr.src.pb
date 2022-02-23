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
    - name: init-zephyr.sh
      basedir: True
      exec: |
        [ -d .west ] || (cd zephyr; west init -l)
        west update
        west zephyr-export
    - name: install-pip.sh
      exec: |
        pip install --user "{{pip_missing|join(' ')}}"
    - name: build-sample.sh
      basedir: repo/zephyr
      exec:
        west build -b cc26x2r1_launchxl samples/hello_world -d launch-hello
    - name: build.sh
      exec:
        ./bin/build-west.sh
        ./bin/install-west.sh
        ./bin/install-pip.sh
        ./bin/init-zephyr.sh
        ./bin/build-sample.sh
    pip_missing:
    - canopen
    - pylink-square
    - anytree
    - junit2html
    - lpc_checksum
    - pillow
    - imgtool
    ENV:
      ZEPHYR_BASE: "{{REPO_DIR}}/zephyr"
      ZEPHYR_TOOLCHAIN_VARIANT: cross-compile
      CROSS_COMPILE: /usr/bin/arm-none-eabi-
    PKGS:
    - ccache
    - device-tree-compiler
    - dfu-util
    - file
    - g++-multilib
    - gcc
    - gcc-multilib
    - gperf
    - libsdl1.2-dev
    - make
    - ninja-build
    - python3-dev
    - python3-setuptools
    - python3-tk
    - python3-wheel
    - wget
    - xz-utils
    # west
    - pykwalify
    - python3-colorama
    - python3-dateutil
    - python3-docopt
    - python3-packaging
    - python3-pykwalify
    - python3-pyparsing
    - python3-ruamel.yaml
    - python3-ruamel.yaml.clib
    - python3-setuptools
    - python3-yaml
    # toolchain
    - binutils-arm-none-eabi
    - gcc-arm-none-eabi
    #- libstdc++-arm-none-eabi-dev
    # toolchain - newlib
    - libnewlib-arm-none-eabi
    - libnewlib-dev
    - libstdc++-arm-none-eabi-newlib
    # toolchain - picolib
    - picolibc-arm-none-eabi
    - libstdc++-arm-none-eabi-picolibc
    # requirements-base. missing: canopen, pylink-square, anytree
    - python3-can
    - python3-intelhex
    - python3-packaging
    - python3-progress
    - python3-psutil
    - python3-pyelftools
    - python3-pykwalify
    - python3-yaml
    # requirements-build-test.
    - gcovr
    - python3-ply
    - python3-colorama
    - python3-coverage
    - python3-pytest
    - mypy
    - python3-mypy
    - python3-mock
    # requirements-compliance.
    - pylint
    - python3-magic
    - python3-junitparser
    # requirements-doc.
    - python3-breathe
    - python3-pygments
    - python3-pykwalify
    - python3-sphinx
    - python3-sphinxcontrib.svg2pdfconverter
    - python3-sphinx-notfound-page
    - python3-sphinx-rtd-theme
    - python3-sphinx-tabs
    - python3-yaml
    # requirements-extras. missing: anytree, junit2html, lpc_checksum, pillow, imgtool
    - gitlint
    - python3-protobuf
    - python3-github
    # requirements-run-test
    - python3-cbor2
    - python3-psutil
    - python3-pyocd
    - python3-serial
    - python3-tabulate
  tasks:
  - include: tasks/compfuzor.includes type=src
