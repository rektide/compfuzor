---
- hosts: all
  vars:
    TYPE: sunshine
    INSTANCE: git
    REPO: https://github.com/LizardByte/Sunshine
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
          sudo setcap -r sunshine
          ln -s $(pwd)/sunshine /usr/local/bin/sunshine
          ln -s $(pwd)/sunshine.service /etc/systemd/service/sunshine.service
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

