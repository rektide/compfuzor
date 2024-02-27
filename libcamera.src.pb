---
- hosts: all
  vars:
    TYPE: libcamera
    INSTANCE: git
    REPO: https://github.com/raspberrypi/libcamera
    PKGS:
      - python3-pip
      - python3-jinja2
      - libboost-dev
      - libgnutls28-dev
      - openssl
      - libtiff5-dev
      - pybind11-dev
      - qtbase5-dev
      - libqt5core5a
      - libqt5gui5
      - libqt5widgets5
      # huge, includes llvm, for some lrelease bin?
      #- qttools5-dev-tools
      - meson
      - cmake
      - ninja-build
      - python3-yaml
      - python3-ply
      - libglib2.0-dev
      - libgstreamer-plugins-base1.0-dev
      - libevent-dev
      - libsdl2-dev
      - libyaml-dev
    BINS:
      - name: build.sh
        exec: |
          time meson setup build ${FLAGS}
          time ninja -C build
      - name: install.sh
        exec: |
          sudo ninja -C build install
    ENV:
      FLAGS: "{{flags|join(' ')}}"
    flags:
      - --buildtype=release
      - -Dpipelines=rpi/vc4,rpi/pisp,uvcvideo,vimc,simple
      - -Dipas=rpi/vc4,rpi/pisp,vimc
      - -Dv4l2=true
      - -Dgstreamer=enabled
      - -Dtest=false
      - -Dlc-compliance=false
      - -Ddocumentation=disabled
      - -Dpycamera=enabled
      - -Dcam=enabled
      - -Dqcam=enabled
      - -Dlc-compliance=disabled
  tasks:
    - include: tasks/compfuzor.includes type=src
