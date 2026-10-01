---
# xdg-desktop-portal-umbriel.src.pb -- ScreenCast/Screenshot portal backend
# for the umbriel compositor.
#
# This is the piece umbriel.src.pb deliberately left uncovered ("a separate
# source project and is intentionally not covered here yet"); installing it
# gives portal-aware clients (browsers, OBS, screenshot tools) working screen
# sharing and screenshots inside umbriel sessions.
#
# Why a plain /usr/local meson install is enough, no extra wiring:
#   * xdg-desktop-portal scans $XDG_DATA_DIRS/xdg-desktop-portal/portals for
#     *.portal and *-portals.conf -- /usr/local/share is on the session's
#     XDG_DATA_DIRS, so umbriel.portal and umbriel-portals.conf are found.
#   * umbriel.desktop sets DesktopNames=Umbriel; the frontend case-folds to
#     `umbriel` and picks umbriel-portals.conf (default=umbriel;gtk).
#   * the D-Bus service lands in /usr/local/share/dbus-1/services, so the
#     backend is bus-activatable; its unit is Type=dbus with
#     SystemdService=, hence the user-manager daemon-reload below.
# The ScreenCast path needs the pipewire daemon (+ wireplumber) at runtime;
# both are in the package lanes.

- hosts: all
  vars:
    TYPE: xdg-desktop-portal-umbriel
    INSTANCE: git
    REPO: https://github.com/noctalia-dev/xdg-desktop-portal-umbriel
    ENV: True

    # Arch packages include their development headers. gtk4 feeds the meson
    # -Dpicker=auto share picker (umbriel-share-picker); without it only the
    # backend daemon builds.
    ARCH_PKGS:
      - cairo
      - gcc
      - git
      - gtk4
      - libdrm
      - libpipewire
      - meson
      - ninja
      - nlohmann-json
      - pipewire
      - pkgconf
      - sdbus-c++
      - tomlplusplus
      - wayland
      - wayland-protocols
      - wireplumber
      - xdg-desktop-portal

    # Install missing source-build dependencies without turning this playbook
    # into an opportunistic workhorse graphics-stack upgrade.
    APT_INSTALL: present
    PKGS:
      - build-essential
      - git
      - libcairo2-dev
      - libdrm-dev
      - libgbm-dev
      - libgtk-4-dev
      - libpipewire-0.3-dev
      - libsdbus-c++-dev
      - libtomlplusplus-dev
      - libwayland-dev
      - meson
      - ninja-build
      - nlohmann-json3-dev
      - pkg-config
      - wayland-protocols
      # runtime, not just -dev: the daemon side of ScreenCast
      - pipewire
      - wireplumber
      - xdg-desktop-portal

    BINS:
      - name: build.sh
        basedir: repo
        content: |
          # Keep Meson/Ninja state local: the archive checkout may be CIFS,
          # where mode/timestamp behavior produces false dirtiness and broken
          # incremental builds (same rationale as umbriel.src.pb build.sh).
          _build="${DIR}/build-release"
          git status --porcelain >/dev/null
          if [ -f "$_build/meson-private/coredata.dat" ]; then
              meson setup "$_build" --reconfigure \
                  --buildtype=release --prefix=/usr/local
          else
              meson setup "$_build" \
                  --buildtype=release --prefix=/usr/local
          fi
          meson compile -C "$_build"
      # The package lanes run first; this main-lane leaf then builds and
      # escalates only installation.
      - name: install-umbriel-portal.sh
        phase: main
        basedir: repo
        content: |
          "${DIR}/bin/build.sh"
          sudo meson install -C "${DIR}/build-release"
          # Some source filesystems preserve executable data-file modes; only
          # the libexec binaries may stay executable. The share picker is
          # -Dpicker=auto (present whenever gtk4 headers were found).
          sudo chmod 0755 /usr/local/libexec/xdg-desktop-portal-umbriel
          [ -x /usr/local/libexec/umbriel-share-picker ] &&
              sudo chmod 0755 /usr/local/libexec/umbriel-share-picker
          sudo chmod 0644 \
              /usr/local/share/xdg-desktop-portal/portals/umbriel.portal \
              /usr/local/share/xdg-desktop-portal/umbriel-portals.conf \
              /usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.umbriel.service \
              /usr/local/lib/systemd/user/xdg-desktop-portal-umbriel.service
          systemctl --user daemon-reload
      - name: status.sh
        compose: false
        content: |
          systemctl --user status xdg-desktop-portal-umbriel.service || true
          busctl --user list 2>/dev/null | grep -iE 'portal|umbriel' || true
      - name: restart.sh
        compose: false
        content: |
          systemctl --user restart xdg-desktop-portal.service
          systemctl --user restart xdg-desktop-portal-umbriel.service || true
  tasks:
    - import_tasks: tasks/compfuzor.includes
