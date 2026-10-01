---
# noctalia.src.pb -- Noctalia v5, the native Wayland desktop shell that pairs
# with umbriel (noctalia-dev/umbriel README wires it in via
# `general.autostart = [ "noctalia" ]`; see also the keybind example
# `spawn:noctalia msg panel-toggle launcher`).
#
# No Qt/GTK: Wayland + OpenGL ES, C++23, meson. Deps and behavior per
# upstream PACKAGING.md/BUILDING.md (vendored: Wuffs, Luau, fzy, Material
# Color Utilities; no system packages for those). Notes that shaped this
# playbook:
#   * packagers are told to call meson directly (the justfile is convenience
#     only) with --buildtype=release and -Dtests=disabled -- exactly what
#     build.sh does; -Dnative_optimizations stays off (portable default).
#   * prefix/datadir are baked into the binary (NOCTALIA_INSTALL_PREFIX/
#     DATADIR), so configure and install share /usr/local here.
#   * shell completions are a packaging step, not a meson install rule:
#     install-noctalia.sh regenerates them from the built binary into
#     /usr/local/share/{bash-completion,zsh,fish} locations.
#   * no systemd unit ships: startup is compositor autostart or the desktop
#     entry (`noctalia --daemon`); control a running shell with
#     `noctalia msg ...` (bin/msg.sh).
# Runtime expectations (documented, not enforced here): pipewire daemon +
# wireplumber (aborts without them -- both are in the package lanes),
# fontconfig fonts, `git` on PATH for plugin sources; optional upower,
# ddcutil, and a Secret Service provider (gnome-keyring.opt.pb covers that
# on this fleet). Noctalia claims org.freedesktop.Notifications and the
# StatusNotifier host on non-Plasma sessions: do not run mako/dunst/swaync
# alongside it.

- hosts: all
  vars:
    TYPE: noctalia
    INSTANCE: git
    REPO: https://github.com/noctalia-dev/noctalia
    ENV: True

    # Arch packages include their development headers. stb must provide
    # stb_image_resize2.h (Arch `stb`, Debian `libstb-dev` both do).
    ARCH_PKGS:
      - cairo
      - curl
      - fontconfig
      - freetype2
      - gcc
      - glib2
      - harfbuzz
      - jemalloc
      - libglvnd
      - libical
      - libpipewire
      - libqalculate
      - libsecret
      - libsodium
      - libsndfile
      - libwebp
      - libxkbcommon
      - libxml2
      - librsvg
      - libjxl
      - md4c
      - meson
      - nlohmann-json
      - ninja
      - pango
      - pkgconf
      - polkit
      - sdbus-cpp
      - stb
      - tomlplusplus
      - wayland
      - wayland-protocols
      # runtime daemons, not just libraries
      - pipewire
      - wireplumber

    # Install missing source-build dependencies without turning this playbook
    # into an opportunistic workhorse graphics-stack upgrade. (Debian 12
    # bookworm would need CXX=g++-13; forky/sid gcc is new enough.)
    APT_INSTALL: present
    PKGS:
      - build-essential
      - git
      - libcairo2-dev
      # gnutls flavor, not the openssl one BUILDING.md lists alongside
      # libqalculate-dev: on Debian the two -dev flavors conflict and
      # libqalculate-dev depends on gnutls, so openssl would evict it
      # (verified the hard way). Noctalia only needs libcurl via pkg-config.
      - libcurl4-gnutls-dev
      - libegl-dev
      - libfontconfig-dev
      - libfreetype-dev
      - libgles-dev
      - libglib2.0-dev
      - libharfbuzz-dev
      - libical-dev
      - libjemalloc-dev
      - libjxl-dev
      - libmd4c-dev
      - libpam0g-dev
      - libpango1.0-dev
      - libpipewire-0.3-dev
      - libpolkit-agent-1-dev
      - libpolkit-gobject-1-dev
      - libqalculate-dev
      - librsvg2-dev
      - libsecret-1-dev
      - libsndfile1-dev
      - libsodium-dev
      - libstb-dev
      - libtomlplusplus-dev
      - libwayland-dev
      - libwebp-dev
      - libwireplumber-0.5-dev
      - libxkbcommon-dev
      - libxml2-dev
      - meson
      - ninja-build
      - nlohmann-json3-dev
      - pkg-config
      - wayland-protocols
      # runtime, not just -dev: noctalia aborts without the pipewire daemon
      - pipewire
      - wireplumber
      - polkitd

    BINS:
      - name: build.sh
        basedir: repo
        content: |
          # Keep Meson/Ninja state local: the archive checkout may be CIFS,
          # where mode/timestamp behavior produces false dirtiness and broken
          # incremental builds (same rationale as umbriel.src.pb build.sh).
          # jemalloc is -Djemalloc=auto (used on glibc when present); tests
          # are a separate target upstream and stay disabled for release.
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
      - name: install-noctalia.sh
        phase: main
        basedir: repo
        content: |
          "${DIR}/bin/build.sh"
          sudo meson install -C "${DIR}/build-release"
          # Completions are generated by the fresh binary (upstream keeps
          # this a packaging step; running the target is fine for local
          # non-cross builds).
          _bin="${DIR}/build-release/noctalia"
          "$_bin" completions bash |
              sudo tee /usr/local/share/bash-completion/completions/noctalia >/dev/null
          "$_bin" completions zsh |
              sudo tee /usr/local/share/zsh/site-functions/_noctalia >/dev/null
          "$_bin" completions fish |
              sudo tee /usr/local/share/fish/vendor_completions.d/noctalia.fish >/dev/null
          # Some source filesystems preserve executable data-file modes; the
          # runtime assets tree is data-only, so blanket de-exec its files.
          sudo find /usr/local/share/noctalia -type f -exec chmod 0644 {} +
          sudo chmod 0644 \
              /usr/local/share/applications/dev.noctalia.Noctalia.desktop \
              /usr/local/share/icons/hicolor/scalable/apps/noctalia.svg \
              /usr/local/share/bash-completion/completions/noctalia \
              /usr/local/share/zsh/site-functions/_noctalia \
              /usr/local/share/fish/vendor_completions.d/noctalia.fish
      - name: run.sh
        compose: false
        content: exec /usr/local/bin/noctalia "$@"
      # IPC to the running shell, e.g. `msg.sh panel-toggle launcher`
      # (umbriel keybinds spawn this).
      - name: msg.sh
        compose: false
        content: exec /usr/local/bin/noctalia msg "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
