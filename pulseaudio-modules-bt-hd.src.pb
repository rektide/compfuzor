---
- hosts: all
  vars:
    TYPE: pulseaudio-module-bt-hd
    INSTANCE: git
    REPO: https://github.com/EHfive/pulseaudio-modules-bt
    BINS:
    - name: build.sh
      exec: |
        #./bin/backup.sh # when snapshot backup
        git submodule update --init
        mkdir -p build
        cd build
        cmake -DCMAKE_INSTALL_PREFIX:PATH={{DIR}}.. # -DFORCE_LARGEST_PA_VERSION+ON
        make
        make install
    - name: backup.sh
      exec: |
        # TODO: make snapshot backup
        MODDIR=`pkg-config --variable=modlibexecdir libpulse`
        sudo find $MODDIR -regex ".*\(bluez5\|bluetooth\).*\.so" -exec cp {} {}.bak \;
    PKGS:
    - libavcodec-dev
    - libavutil-dev
    - libfdk-aac-dev
    - libdbus-1-dev
    - libbluetooth-dev
    - libsbc-dev
    - libpulse-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
