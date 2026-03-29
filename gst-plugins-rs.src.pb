---
- hosts: all
  vars:
    TYPE: gst-plugins-rs
    INSTANCE: git
    REPO: https://github.com/GStreamer/gst-plugins-rs
    RUST: True
    PKGS:
      - cargo-c
      - libgstreamer1.0-dev
      - libgstreamer-plugins-base1.0-dev
      - gstreamer1.0-plugins-base
      - libglib2.0-dev
      - libxml2-dev
      - liborc-0.4-dev
    BINS:
      - name: build.sh
        content: |
          cargo build --release
      - name: install.sh
        sudo: True
        content: |
          cargo cinstall --prefix=/usr --libdir /usr/lib/x86_64-linux-gnu
  tasks:
    - import_tasks: tasks/compfuzor.includes
