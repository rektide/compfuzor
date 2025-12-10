---
- hosts: all
  vars:
    TYPE: niri
    INSTANCE: git
    REPO: https://github.com/YaLTeR/niri
    ENV: True
    # arch recommendations
    PKGS:
      - alacritty
      - fuzzel
      # resolution switching
      - kanshi
      - mako
      - swaybg
      #- swayidle
      - swaylock
      - waybar
      - xdg-desktop-portal-gtk
      - xdg-desktop-portal-gnome
      # and xwayland-satellite
      - xwayland
      #- udiskie
    ETC_FILES:
      - name: config-overlay.kdl
        content: |
          binds {
            Mod+T hotkey-overlay-title="Open a Terminal: kitty" { spawn "kitty"; }
            Mod+D hotkey-overlay-title="Run an Application: vicinae" { spawn-sh "vicinae toggle"; }
            Alt+Grave hotkey-overlay-title="Vicinae clipboard" { spawn-sh "vicinae vicinae://extensions/vicinae/clipboard/history"; }
          }
    BINS:
      - name: build.sh
        content: cargo build --release
      - name: install.sh
        content: |
          # https://github.com/YaLTeR/niri/wiki/Packaging-niri
          ln -sfv $(pwd)/target/release/niri $GLOBAL_BINS_DIR/
          ln -sfv $(pwd)/target/release/niri /usr/bin/niri
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
