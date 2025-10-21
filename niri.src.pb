---
- hosts: all
  vars:
    TYPE: niri
    INSTANCE: git
    REPO: https://github.com/YaLTeR/niri
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        content: cargo build --release
      - name: install.sh
        content: |
          # https://github.com/YaLTeR/niri/wiki/Packaging-niri
          ln -sfv $(pwd)/target/release/niri $GLOBAL_BINS_DIR/
          ln -sfv $(pwd)/resources/niri-session $GLOBAL_BINS_DIR/
          ln -sfv $(pwd)/resources/niri.desktop /usr/share/wayland-sessions/
          ln -sfv $(pwd)/resources/niri-portals.conf /usr/share/xdg-desktop-portal/
          #ln -sfv $(pwd)/resources/niri.service /usr/lib/systemd/user/
          ln -sfv $(pwd)/resources/niri.service /etc/systemd/user/
          ln -sfv $(pwd)/resources/niri-shutdown.target /etc/systemd/user/
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
    - import_tasks: tasks/compfuzor.includes
