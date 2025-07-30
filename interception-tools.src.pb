---
- # note: now included in debian
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
    - libboost-container-dev
    ETC_FILES:
    - name: caps2esc.yaml
      content: |
        - JOB: "intercept -g $DEVNODE | caps2esc | uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
    BINS_DIR: "{{ OPT }}/bin"
    LINKS:
    #- key: bin
    #  value: "{{ BINS_DIR }}"
      bin: "{{ BINS_DIR }}"
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
      basedir: True
      exec: |
        ./bin/build-interception-tools.sh
        ./bin/build-caps2esc.sh
    # links to built resource
    - name: caps2esc
      src: false
      global: true
      delay: postRun
    - name: intercept
      src: false
      global: true
      delay: postRun
    - name: udevmon
      src: false
      global: true
      delay: postRun
    - name: uinput
      src: false
      global: true
      delay: postRun
    PKGS:
    - libboost-dev
    - libevdev-dev
    - libudev-dev
    - libyaml-cpp-dev
  tasks:
  - import_tasks: tasks/compfuzor.includes
