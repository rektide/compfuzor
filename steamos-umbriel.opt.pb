---
- hosts: all
  vars:
    TYPE: steamos-umbriel
    INSTANCE: main
    REPO: https://github.com/noctalia-dev/umbriel
    ENV: True

    # Best-effort SteamOS source-build route. /opt and the archive checkout
    # persist across image swaps; /usr does not. Re-run bin/install.sh after a
    # SteamOS update to restore packages, Umbriel, session files, and units.
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

    BINS:
      # This body precedes package/main children in the composed installer.
      - name: install.sh
        content: sudo steamos-readonly disable
      - name: build.sh
        basedir: repo
        content: |
          _build="${DIR}/build-release"
          git status --porcelain >/dev/null
          rm -rf "$_build"
          meson setup "$_build" \
              --buildtype=release --prefix=/usr -Dtests=disabled
          meson compile -C "$_build"
      - name: install-umbriel.sh
        phase: main
        basedir: repo
        content: |
          "${DIR}/bin/build.sh"
          sudo meson install -C "${DIR}/build-release"
          sudo chmod 0644 \
              /usr/lib/systemd/user/umbriel.service \
              /usr/lib/systemd/user/umbriel-session.target \
              /usr/lib/systemd/user/umbriel-shutdown.target \
              /usr/share/wayland-sessions/umbriel.desktop \
              /usr/share/umbriel/config.toml \
              /usr/share/umbriel/shaders/reveal.glsl \
              /usr/share/umbriel/shaders/squash.glsl
          systemctl --user daemon-reload
      - name: validate.sh
        compose: false
        content: /usr/bin/umbriel validate "$@"
      - name: run-nested.sh
        compose: false
        content: exec /usr/bin/start-umbriel "$@"
      - name: session.sh
        compose: false
        content: |
          set -e
          steamosctl get-valid-desktop-sessions | grep -w umbriel.desktop || {
              echo "session: umbriel.desktop was not registered by the install" >&2
              exit 1
          }
          steamosctl set-default-desktop-session umbriel.desktop
          steamosctl get-default-desktop-session
      - name: session-plasma.sh
        compose: false
        content: steamosctl set-default-desktop-session plasma.desktop
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        # Persistent SteamOS home-partition offload.
        type: opt
