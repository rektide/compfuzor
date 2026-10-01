---
# Vibepollo -- Nonary's AI-heavy fork of Apollo (itself a Sunshine fork).
# Still a drop-in Sunshine replacement: the CMake target is `sunshine`, config
# dir is still ~/.config/sunshine, FQDN is still dev.lizardbyte.app.Sunshine
# (user unit app-dev.lizardbyte.app.Sunshine.service, Alias=sunshine.service).
# Installing this overwrites any existing sunshine binary at the same path.
# Pair with sunshine.opt.pb (csrf_allowed_origins) -- the config file and
# block name are unchanged.
#
# Build deps follow upstream scripts/linux_build.sh (Debian set) minus
# packaging/docs/cuda entries. Notably:
#  - no libboost-*-dev: Vibepollo requires Boost >= 1.89 via
#    find_package(Boost CONFIG), but Debian's BoostConfig has no boost_system
#    component, so CMake always falls back to FetchContent-building boost
#    1.89 from the upstream tarball. The apt packages would be dead weight.
#  - cmake + ninja-build arrive via the cmake subsystem contrib.
#  - libudev-dev + libsystemd-dev are load-bearing beyond linking: their
#    pkg-config files steer `cmake --install` to emit 60-sunshine.rules
#    (/lib/udev/rules.d), the systemd user unit, and the uhid modules-load.d
#    conf, so no manual copies are needed.
#
# Flow: the playbook clones (with submodules) and builds via the generated
# build-cmake.sh. System install is operator-run afterwards:
#   sudo bin/install.sh          # cmake --install + caps + udev reload
#   systemctl --user enable --now sunshine
- hosts: all
  vars:
    TYPE: vibepollo
    INSTANCE: git
    REPO: https://github.com/Nonary/Vibepollo
    GIT_SUBMODULES: True
    CMAKE: True
    # Deb layout, matching upstream linux_build.sh: binary /usr/bin/sunshine,
    # assets /usr/share/sunshine. CUDA stays off (no toolkit on this host and
    # CUDA_FAIL_ON_MISSING would abort the configure).
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
      - libayatana-appindicator3-dev  # tray
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
      - libsystemd-dev
      - libudev-dev
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
