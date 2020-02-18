---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: git
    REPOS:
      interception-tools: https://gitlab.com/interception/linux/tools
      caps2esc: https://gitlab.com/interception/linux/plugins/caps2esc
    OPT_DIR: true
    PKGS:
    - libevdev-dev
    - libyaml-cpp-dev
    - libudev-dev
    ETC_FILES:
    - name: caps2esc.yaml
      content: |
        - JOB: "intercept -g $DEVNODE | caps2esc | uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
    BINS:
    - name: build-interception-tools.sh
      basedir: interception-tools
      exec: |
        mkdir -p build
        cd build
        cmake -DCMAKE_INSTALL_PREFIX={{OPT}} ..
        make
        make install
    - name: build-caps2esc.sh
      basedir: caps2esc
      exec: |
        mkdir -p build
        cd build
        cmake -DCMAKE_INSTALL_PREFIX={{OPT}} ..
        make
        make install
    - name: build.sh
      run: true
      exec: |
        ./bin/build-interception-tools.sh
        ./bin/build-caps2esc.sh
    # links to built resource
    - name: caps2esc
      src: false
      global: true
    - name: intercept
      src: false
      global: true
    - name: udevmon
      src: false
      global: true
    - name: uinput
      src: false
      global: true
  tasks:
  - include: tasks/compfuzor.includes type=src
