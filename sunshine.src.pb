---
- hosts: all
  vars:
    TYPE: sunshine
    INSTANCE: git
    REPO: https://github.com/LizardByte/Sunshine
    CMAKE: True
    CMAKE_ARGS: '-DSUNSHINE_ENABLE_CUDA=OFF'
    MODULES:
      - uinput
    BINS:
      # TODO: a cmake that uses ninja for build would be nice
      - name: install.sh
        basedir: repo/build
        generatedAt: False
        exec: |
          sudo setcap cap_sys_admin,cap_sys_nice+p sunshine
          # -E so my asdf works
          #sudo -E make install
          #ln -sfv $(pwd) $GLOBAL_BINS_DIR
          sudo ninja install
          # linking rules seems not to work, copy
          sudo cp ../src_assets/linux/misc/60-sunshine.rules /etc/udev/rules.d/60-sunshine.rules
          #sudo udevadm control --reload-rules
          #sudo udevadm trigger
      - name: apply-udev.sh
        content: |
          sudo udevadm control --reload-rules
          sudo udevadm trigger
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
      - libmfx-gen-dev
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
    - import_tasks: tasks/compfuzor.includes

