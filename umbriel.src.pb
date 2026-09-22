---
- hosts: all
  vars:
    TYPE: umbriel
    INSTANCE: git
    REPO: https://github.com/noctalia-dev/umbriel
    ENV: True

    # Arch packages include their development headers. xdg-desktop-portal-
    # umbriel is a separate source project and is intentionally not covered
    # here yet.
    ARCH_PKGS:
      - cairo
      - gcc
      - git
      - jemalloc
      - kitty
      - lcms2
      - libdrm
      - libinput
      - libxkbcommon
      - mesa
      - meson
      - ninja
      - nlohmann-json
      - pango
      - pixman
      - pkgconf
      - systemd-libs
      - tomlplusplus
      - wayland
      - wayland-protocols
      - wlroots0.20
      - xwayland-satellite

    # Install missing source-build dependencies without turning this playbook
    # into an opportunistic workhorse graphics-stack upgrade.
    APT_INSTALL: present
    PKGS:
      - build-essential
      - git
      - kitty
      - libcairo2-dev
      - libdrm-dev
      - libegl-dev
      - libgbm-dev
      - libgles2-mesa-dev
      - libinput-dev
      - libjemalloc-dev
      - liblcms2-dev
      - libpango1.0-dev
      - libpixman-1-dev
      - libtomlplusplus-dev
      - libudev-dev
      - libwayland-dev
      - libwlroots-0.20-dev
      - libxkbcommon-dev
      - meson
      - ninja-build
      - nlohmann-json3-dev
      - pkg-config
      - wayland-protocols

    BINS:
      - name: build.sh
        basedir: repo
        content: |
          # Keep Meson/Ninja state local: the archive checkout may be CIFS,
          # where mode/timestamp behavior produces false dirtiness and broken
          # incremental builds.
          _build="${DIR}/build-release"
          git status --porcelain >/dev/null
          if [ -f "$_build/meson-private/coredata.dat" ]; then
              meson setup "$_build" --reconfigure \
                  --buildtype=release --prefix=/usr/local -Dtests=disabled
          else
              meson setup "$_build" \
                  --buildtype=release --prefix=/usr/local -Dtests=disabled
          fi
          meson compile -C "$_build"
      # The package lanes run first; this main-lane leaf then builds and
      # escalates only installation.
      - name: install-umbriel.sh
        phase: main
        basedir: repo
        content: |
          "${DIR}/bin/build.sh"
          sudo meson install -C "${DIR}/build-release"
          # Some source filesystems preserve executable data-file modes.
          sudo chmod 0644 \
              /usr/local/lib/systemd/user/umbriel.service \
              /usr/local/lib/systemd/user/umbriel-session.target \
              /usr/local/lib/systemd/user/umbriel-shutdown.target \
              /usr/local/share/wayland-sessions/umbriel.desktop \
              /usr/local/share/umbriel/config.toml \
              /usr/local/share/umbriel/shaders/reveal.glsl \
              /usr/local/share/umbriel/shaders/squash.glsl
          systemctl --user daemon-reload
      - name: validate.sh
        compose: false
        content: /usr/local/bin/umbriel validate "$@"
      - name: run-nested.sh
        compose: false
        content: exec /usr/local/bin/start-umbriel "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
