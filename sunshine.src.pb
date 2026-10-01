---
# Sunshine -- LizardByte upstream. Apollo (apollo.src.pb) and Vibepollo
# (vibepollo.src.pb) both install over the same binary/config layout; keep
# only one of the three installed at a time.
# Pair with sunshine.opt.pb (csrf_allowed_origins).
#
# Refreshed against Sunshine's scripts/linux_build.sh:
#  - tray moved to Qt6 (third-party/tray QtTrayMenu): ayatana appindicator
#    is out, qt6-base-dev + qt6-svg-dev are in.
#  - no libboost-*-dev: Sunshine pins Boost 1.89 EXACT via
#    find_package(Boost CONFIG), which never matches Debian's BoostConfig
#    (no boost_system component), so CMake always FetchContent-builds 1.89.
#  - libudev-dev + libsystemd-dev steer `cmake --install` to emit
#    60-sunshine.rules, the systemd user unit, and the uhid modules-load.d
#    conf.
#
# Flow: the playbook clones (with submodules) and builds via the generated
# build-cmake.sh. System install is operator-run afterwards:
#   sudo bin/install.sh          # cmake --install + caps + udev reload
#   systemctl --user enable --now sunshine
- hosts: all
  vars:
    TYPE: sunshine
    INSTANCE: git
    REPO: https://github.com/LizardByte/Sunshine
    GIT_SUBMODULES: True
    CMAKE: True
    # Deb layout, matching upstream linux_build.sh: binary /usr/bin/sunshine,
    # assets /usr/share/sunshine. CUDA stays off (no toolkit on this host).
    CMAKE_ARGS: >-
      -DSUNSHINE_ENABLE_CUDA=OFF
      -DBUILD_TESTS=OFF
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
      - qt6-base-dev                   # tray (Qt6 since the third-party/tray rework)
      - qt6-svg-dev
      - libcap-dev                    # KMS
      - libcurl4-openssl-dev
      - libdrm-dev                    # KMS
      - libevdev-dev
      - libgbm-dev
      - libminiupnpc-dev
      - libnotify-dev
      - libnuma-dev
      - libopus-dev
      - libpipewire-0.3-dev           # KWin/portal capture
      - libpulse-dev
      - libssl-dev
      - libsystemd-dev                # systemd unit + modules-load.d install paths
      - libudev-dev                   # udev rules install path
      - libva-dev                     # VA-API
      - libvulkan-dev                 # Vulkan encode
      - libwayland-dev
      - libx11-dev
      - libxcb-shm0-dev
      - libxcb-xfixes0-dev
      - libxcb1-dev
      - libxfixes-dev
      - libxrandr-dev
      - libxtst-dev
      - glslang-tools                 # Vulkan shader compiler
      - python3-jinja2                # glad loader generation
      - python3-setuptools            # glad pkg_resources
      - nodejs                        # web UI (npm ci inside the cmake web_ui target)
      - npm
  tasks:
    - import_tasks: tasks/compfuzor.includes
