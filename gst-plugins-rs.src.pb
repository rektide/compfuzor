---
- hosts: all
  vars:
    TYPE: gst-plugins-rs
    INSTANCE: git
    REPO: https://github.com/GStreamer/gst-plugins-rs
    RUST: True
    CARGO_BUILD: cbuild
    RUST_CARGO_INSTALL: "cargo cinstall --prefix=/usr --libdir /usr/lib/x86_64-linux-gnu"
    PKGS:
      - cargo-c
      - libgstreamer1.0-dev
      - libgstreamer-plugins-base1.0-dev
      - gstreamer1.0-plugins-base
      - libglib2.0-dev
      - libxml2-dev
      - liborc-0.4-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
