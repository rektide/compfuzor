---
- hosts: all
  vars:
    TYPE: scrcpy
    INSTANCE: git
    REPO: https://github.com/Genymobile/scrcpy
    ENVS:
      ANDROID_SDK_ROOT: /usr/lib/android-sdk
    PKGS:
      # runtime
      - ffmpeg
      - libsdl2-dev
      - adb
      - adbd
      - libusb-1.0-0-dev
      # client
      - gcc
      - git
      - pkg-config
      - meson
      - ninja-build
      - libsdl2-dev
      - libavcodec-dev
      - libavdevice-dev
      - libavformat-dev
      - libavutil-dev
      - libswresample-dev
      - libusb-1.0-0-dev
      # android
      - android-sdk-platform-tools
      - android-sdk-platform-tools-base
      - android-sdk-platform-tools-common
      # ed: i'm just throwing this in for no reason?
      - libandroid-ddms-java
      - etc1tool
      #- google-android-platform-35-installer
      #- google-android-platform-tools-installer
      - google-android-build-tools-34.0.0-installer
      - google-android-platform-34-ext12-installer
      - gradle
      - google-android-m2repository-installer
    BINS:
      - name: build.sh
        exec: |
          meson setup x --buildtype=release --strip -Db_lto=true
          ninja  -Cx
      - name: install.sh
        sudo: True
        exec: |
          ninja -Cx install
  tasks:
    - import_tasks: tasks/compfuzor.includes
