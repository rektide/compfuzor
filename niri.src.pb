---
- hosts: all
  vars:
    TYPE: niri
    INSTANCE: git
    REPO: https://github.com/YaLTeR/niri
    BINS:
      - name: build.sh
        exec: cargo build --release
    PKGS:
      # also: clang
      - libudev-bin
      - libgbm-dev
      - libxkbcommon-dev
      - libegl1-mesa-dev
      - libwayland-dev
      - libinput-dev
      - libdbus-1-dev
      - libsystemd-dev
      - libseat-dev
      - libpipewire-0.3-dev
      - libpango1.0-dev
  tasks:
    - include: tasks/compfuzor.includes type=src
