---
- hosts: all
  vars:
    TYPE: pulseaudio
    INSTANCE: git
    REPO: https://gitlab.freedesktop.org/pulseaudio/pulseaudio
    PKGS:
    - bash-completion
    - check
    - gstreamer1.0-plugins-rtp
    - libasyncns-dev
    - libasound2-dev
    - libavahi-client-dev
    - libbluetooth-dev
    - libdbus-1-dev
    - libfftw3-dev
    - libglib2.0-dev
    - libgstreamer1.0-dev
    - libgstreamer-plugins-base1.0-dev
    - libgtk-3-dev
    - libgtkmm-3.0-dev
    - libice-dev
    - liblirc-dev
    - libjack-jackd2-dev
    - libsamplerate-dev
    - libsbc-dev
    - libsm-dev
    - libsndfile-dev
    - libsoxr-dev
    - libspeexdsp-dev
    - libssl-dev
    - libsystemd-dev
    - libtdb-dev
    - libudev-dev
    - liborc-dev
    - libwebrtc-audio-processing-dev
    - libxml2-utils
    - libx11-xcb-dev
    OPT_DIR: True
    BINS:
    - name: build.sh
      exec: |
        meson builddir -Dprefix={{OPT}} && \
        cd builddir && \
        ninja && \
        ninja install
  tasks:
  - include: tasks/compfuzor.includes type=src
