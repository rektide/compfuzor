---
- hosts: all
  vars:
    TYPE: rpicam
    INSTANCE: git
    REPO: https://github.com/raspberrypi/rpicam-apps
    BINS:
      - name: build.sh
        exec: |
          time meson setup build ${FLAGS}
          time meson compile -C build
      - name: install.sh
        exec: |
          sudo meson install -C build
          sudo ldconfig
    PKGS:
      - libcamera-dev
      - libjpeg-dev
      - libtiff5-dev
      - libpng-dev
      - libepoxy-dev
      - libavcodec-dev
      - libavdevice-dev
      - libavformat-dev
      - libswresample-dev
      - qtbase5-dev
      - libqt5core5a
      - libqt5gui5
      - libqt5widgets5
      - meson
      - cmake
      - libboost-program-options-dev
      - libdrm-dev
      - libexif-dev
      - ninja-build
      - libopencv-dev
      - libopencv-core-dev
    ENV:
      FLAGS: "{{flags|join(' ')}}"
    FLAGS:
      # 32 bit only?
      - -Dneon_flags=armv8-neon
      - -Denable_libav=true
      - -Denable_drm=true
      - -Denable_egl=true
      - -Denable_qt=true
      - -Denable-opencv=true
      #- -Denable_tflite=true
      - -Denable_tflite=false
  tasks:
    - include: tasks/compfuzor.includes type=src
