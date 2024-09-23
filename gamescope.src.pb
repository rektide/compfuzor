---
- hosts: all
  vars:
    TYPE: gamescope
    INSTANCE: git
    REPO: https://github.com/ValveSoftware/gamescope
    BINS:
      - name: build.sh
        exec: |
          git submodule update --init
          meson build/
          ninja -C build/
          # build/gamescope -- <game>
      - name: install.sh
        exec: |
          sudo setcap 'cap_sys_nice=eip' build/src/gamescope
          sudo meson install -C build/ --skip-subprojects
      - name: run.sh
        exec: |
          # --ready-fd --rt
          gamescope --steam --expose-wayland --hdr-enabled --hdr-itm-enable --hide-cursor-delay 8000 --fade-out-duration 500 --xwayland-count 2 -W 2560 -H 1440 -O DP-3 -- steam -gamepadui -steamdeck -pipewire-dmabuf
    PKGS:
      - libavif-dev
      - libglm-dev
      - libeis-dev
  tasks:
    - include: tasks/compfuzor.includes type=src
