---
# Apollo -- ClassicOldSong's Sunshine fork.
# Drop-in replacement: CMake target is still `sunshine`, config dir is still
# ~/.config/sunshine, FQDN is still dev.lizardbyte.app.Sunshine. Installing
# this overwrites any existing sunshine binary at the same path.
# Pair with sunshine.opt.pb (csrf_allowed_origins) -- the config file and
# block name are unchanged.
- hosts: all
  vars:
    TYPE: apollo
    INSTANCE: git
    REPO: https://github.com/ClassicOldSong/Apollo
    GIT_SUBMODULES: True
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
