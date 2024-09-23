---
- hosts: all
  vars:
    TYPE: sunshine
    INSTANCE: git
    REPO: https://github.com/LizardByte/Sunshine
    MODULES:
      - uinput
    BINS:
      - name: build.sh
        exec: |
          mkdir -p build
          cd build
          cmake ..
          make
      - name: install.sh
        basedir: build
        exec: |
          # -E so my asdf works
          for f in sunshine*dirty
          do
            sudo setcap 'cap_sys_admin+p' $f
          done
          sudo -E make install
          for f in /usr/local/bin/sunshine*dirty
          do
            sudo setcap 'cap_sys_admin+p' $f
          done
          # linking seems not to work maybe??
          sudo cp ../etc/sunshine-udev.rule /etc/udev/rules.d/80-sunshine-udev.rules
          #sudo udevadm control --reload-rules
          #sudo udevadm trigger
      - name: install.user.sh
        basedir: True
        exec: |
          mkdir -p ~/.config/sunshine
          ln -sf $(pwd)/src_assets/linux/assets/apps.json ~/.config/sunshine/
    ETC_FILES:
      - name: sunshine-udev.rule
        content: |
          # highly suspect debian already does essentially this?
          KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess"
    PKGS: 
      - build-essential
      - cmake
      - libayatana-appindicator3-dev
      - libboost-filesystem-dev
      - libboost-locale-dev
      - libboost-log-dev
      - libboost-program-options-dev
      - libcap-dev
      - libdrm-dev
      - libcurl4-openssl-dev
      - libevdev-dev
      - libminiupnpc-dev
      - libmfx-dev
      - libnotify-dev
      - libnuma-dev
      - libopus-dev
      - libpulse-dev
      - libssl-dev
      - libva-dev
      - libvdpau-dev
      - libwayland-dev
      - nodejs
      - npm
  tasks:
    - include: tasks/compfuzor.includes type=src

