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
    BINS:
      - name: build.sh
        generatedAt: "none"
        content: |
          cargo cbuild --release
      - name: install.sh
        generatedAt: "none"
        sudo: True
        content: |
          cargo cinstall --prefix=/usr --libdir /usr/lib/x86_64-linux-gnu
      - name: install-user.sh
        generatedAt: "none"
        content: |
          cargo cinstall --prefix=$HOME/.local --libdir $HOME/.local/lib
  tasks:
    - import_tasks: tasks/compfuzor.includes
