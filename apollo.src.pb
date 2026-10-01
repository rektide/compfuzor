---
# Apollo -- ClassicOldSong's Sunshine fork.
# Drop-in replacement: CMake target is still `sunshine`, config dir is still
# ~/.config/sunshine, FQDN is still dev.lizardbyte.app.Sunshine. Installing
# this overwrites any existing sunshine binary at the same path.
# Pair with sunshine.opt.pb (csrf_allowed_origins) -- the config file and
# block name are unchanged.
#
# Refreshed against Apollo's scripts/linux_build.sh:
#  - no libboost-*-dev: Apollo pins Boost 1.89 EXACT via find_package(Boost
#    CONFIG), which never matches Debian's BoostConfig (no boost_system
#    component), so CMake always FetchContent-builds 1.89. The apt packages
#    would be dead weight.
#  - libudev-dev + libsystemd-dev steer `cmake --install` to emit
#    60-sunshine.rules, the systemd user unit, and the uhid modules-load.d
#    conf (Apollo's own dep script omits them because its CI packages via
#    cpack+postinst instead of installing directly).
#
# Flow: the playbook clones (with submodules) and builds via the generated
# build-cmake.sh. System install is operator-run afterwards:
#   sudo bin/install.sh          # cmake --install + caps + udev reload
#   systemctl --user enable --now sunshine
- hosts: all
  vars:
    TYPE: apollo
    INSTANCE: git
    REPO: https://github.com/ClassicOldSong/Apollo
    GIT_SUBMODULES: True
    CMAKE: True
    # Deb layout, matching upstream linux_build.sh: binary /usr/bin/sunshine,
    # assets /usr/share/sunshine. CUDA stays off (no toolkit on this host).
    # BUILD_TESTS already defaults off upstream.
    CMAKE_ARGS: >-
      -DSUNSHINE_ENABLE_CUDA=OFF
      -DCMAKE_INSTALL_PREFIX=/usr
      -DSUNSHINE_ASSETS_DIR=share/sunshine
    CMAKE_INSTALL: True
    MODULES:
      - uinput
      - uhid  # DS5 emulation, mirrors upstream 60-sunshine.conf
    BINS:
      # Runs after install-cmake.sh's `cmake --install` via the units phase
      # lane of the generated install.sh compositor. Mirrors upstream postinst:
      # caps for KMS grab, udev reload for the fresh 60-sunshine.rules.
      - name: install-system.sh
        phase: units
        exec: |
          sudo setcap cap_sys_admin,cap_sys_nice+p /usr/bin/sunshine
          sudo udevadm control --reload-rules
          sudo udevadm trigger --property-match=DEVNAME=/dev/uinput
          sudo udevadm trigger --property-match=DEVNAME=/dev/uhid
          sudo modprobe uhid
    PKGS:
      - build-essential
      - libayatana-appindicator3-dev  # tray (upstream script omits it; CI builds trayless)
      - libcap-dev                    # KMS
      - libcurl4-openssl-dev
      - libdrm-dev                    # KMS
      - libevdev-dev
      - libgbm-dev
      - libminiupnpc-dev
      - libnotify-dev
      - libnuma-dev
      - libopus-dev
      - libpulse-dev
      - libssl-dev
      - libsystemd-dev                # systemd unit + modules-load.d install paths
      - libudev-dev                   # udev rules install path
      - libva-dev                     # VA-API
      - libwayland-dev
      - libx11-dev
      - libxcb-shm0-dev
      - libxcb-xfixes0-dev
      - libxcb1-dev
      - libxfixes-dev
      - libxrandr-dev
      - libxtst-dev
      - nodejs                        # web UI (npm ci inside the cmake web_ui target)
      - npm
  tasks:
    - import_tasks: tasks/compfuzor.includes
