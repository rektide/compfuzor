---
# DevL0rd/Konveyor -- scrolling column tiling as a KWin effect for Plasma 6.
# Needs Plasma >= 6.4 on a Wayland session (Debian stable/trixie ships 6.3:
# too old; testing/sid or Arch are fine).
#
# Source-only upstream: the effect builds against the exact running KWin, so
# there are no distro packages to consume. This playbook keeps the checkout
# and converges the build deps per family (PKGS -> aptlane, ARCH_PKGS ->
# archlane), then hands off to upstream's own installer:
#
#   bash bin/install.sh
#     # packages lane -> install-konveyor.sh -> upstream ./install.sh
#     #   --skip-deps --no-pull (deps already converged; compfuzor owns the
#     #   checkout). Upstream builds, installs to /usr (sudo), enables the
#     #   effect live (usually no logout) and installs the Konveyor widgets
#     #   + Kontrol Panel launcher swap.
#
# Updates:
#   Arch: upstream registers a pacman hook (konveyor-rebuild.hook) that pulls
#     this checkout and rebuilds on system updates. Hands-off after install.
#   Debian: no hook exists -- after each Plasma/KWin upgrade (or to pick up
#     new commits) re-run the playbook, then `bash bin/install.sh` again.
#
# Remove: `bash bin/uninstall-konveyor.sh` (upstream uninstall: restores
#   shortcuts, window rules and the old launcher).
#
# On a SteamOS device use steamos-konveyor.opt.pb instead: it keeps the
# toolchain off the tiny read-only rootfs via a /opt chroot.
- hosts: all
  vars:
    TYPE: konveyor
    INSTANCE: git
    REPO: https://github.com/DevL0rd/Konveyor
    GIT_SUBMODULES: True
    # upstream extras/packaging/dependencies.sh DEBIAN_PACKAGES, verbatim
    PKGS:
      - cmake
      - ninja-build
      - git
      - g++
      - extra-cmake-modules
      - qt6-base-dev
      - qt6-base-private-dev
      - qt6-declarative-dev
      - kwin-dev
      - libkf6globalaccel-dev
      - libkf6config-dev
      - libkf6colorscheme-dev
      - libkf6notifications-dev
      - libkf6coreaddons-dev
      - libkf6i18n-dev
      - libxkbcommon-dev
      - python3-dbus
      - qml6-module-org-kde-kirigami
      - qml6-module-org-kde-layershell
      - libkf6kcmutils-dev
      - qml6-module-org-kde-kcmutils
      - qml6-module-org-kde-kirigamiaddons-formcard
      - qml6-module-org-kde-kquickcontrols
      - libkf6service-dev
      - libvulkan-dev
      - python3
      - jq
      - curl
      - openssh-client
    # upstream extras/packaging/dependencies.sh ARCH_PACKAGES, verbatim
    # (Arch ships headers inside the runtime packages, so this is mostly
    # already present on a Plasma desktop: --needed skips the rest)
    ARCH_PKGS:
      - base-devel
      - cmake
      - ninja
      - git
      - extra-cmake-modules
      - qt6-base
      - qt6-declarative
      - kwin
      - kglobalaccel
      - kconfig
      - kcolorscheme
      - knotifications
      - kcoreaddons
      - ki18n
      - libxkbcommon
      - python-dbus
      - kirigami
      - layer-shell-qt
      - kcmutils
      - kirigami-addons
      - kdeclarative
      - kservice
      - kdecoration
      - kwindowsystem
      - vulkan-headers
      - vulkan-icd-loader
      - wayland
      - libepoxy
      - libdrm
      - python
      - jq
      - curl
      - openssh
      - glib2
      - libkscreen
      - qt6-tools
      - kpackage
    BINS:
      # main lane leaf of bin/install.sh: the packages lane has converged
      # PKGS/ARCH_PKGS before this runs.
      - name: install-konveyor.sh
        content: |
          set -e
          # upstream install.sh refuses to run as root; it sudo's itself.
          # Drop back to the invoking desktop user when called via
          # `sudo bash bin/install.sh`.
          if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
              exec sudo -u "${SUDO_USER}" -- "${DIR}/bin/install-konveyor.sh" "$@"
          fi
          # Konveyor needs Plasma >= 6.4 on Wayland
          if command -v plasmashell >/dev/null 2>&1; then
              plasmashell --version | awk '{split($2,v,"."); if (v[1]<6 || (v[1]==6 && v[2]<4)) exit 1}' \
                  || { plasmashell --version >&2; \
                       echo "konveyor: Plasma >= 6.4 (Wayland session) required" >&2; exit 1; }
          else
              echo "konveyor: plasmashell not found -- run from inside the Plasma session" >&2
              exit 1
          fi
          # canonical checkout: DIR/repo (symlink into ~/archive via
          # ARCHIVE_DOWNLOAD), kept fresh by this playbook's repo tasks
          cd "${DIR}/repo"
          ./install.sh --skip-deps --no-pull
      - name: uninstall-konveyor.sh
        content: |
          set -e
          if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
              exec sudo -u "${SUDO_USER}" -- "${DIR}/bin/uninstall-konveyor.sh" "$@"
          fi
          cd "${DIR}/repo"
          ./uninstall.sh "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
