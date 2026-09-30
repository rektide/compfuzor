---
- hosts: all
  vars:
    TYPE: niri
    INSTANCE: git
    # niri moved from YaLTeR/niri to the niri-wm org. The canonical jj
    # archive at ~/archive/niri-wm/niri backs this deployment;
    # repo_jj_archive.tasks keeps a dedicated colocated jj/Git workspace at
    # DIR/repo (a repo symlink pointing straight at the archive is admitted
    # by the deploy runner and replaced with that workspace).
    REPO: https://github.com/niri-wm/niri
    GIT_VERSION: main
    ENV: True
    # Rust lane: build-rust.sh cargo-builds the workspace (release default)
    # and install-rust.sh links repo/target/release/niri into
    # GLOBAL_BINS_DIR (RUST_BIN defaults to the TYPE name). install-usr.sh
    # below auto-joins the generated install.sh composite (main phase, after
    # the packages lane) to link the session/desktop/portal/systemd
    # resources; the binary itself stays owned by the rust lane.
    RUST: True
    README: |
      # niri-git — niri deployment (niri-wm archive lane)

      niri moved upstream from `YaLTeR/niri` to the **niri-wm** org; this
      deployment was migrated off the old in-place DIR clone onto the archive
      lane. The old `~/archive/YaLTeR/niri` checkout is decommissioned.

      ## Layout

      - Canonical jj archive: `~/archive/niri-wm/niri` (bookmarks, user
        commits, preserved snapshots live here).
      - Deployment workspace: `{{DIR}}/repo`, a dedicated colocated jj/Git
        workspace of the archive maintained by
        [`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks),
        tracking `main` (`GIT_VERSION: main`).
      - Generated: `bin/` (build.sh, install.sh), `env`/`env.export`, `etc`
        symlink to `/etc/opt/niri-git` (config-overlay.kdl).

      ## Build & install

          bin/build.sh        # rust lane: cargo build --release in repo/
          sudo bin/install.sh # composite: install-apt.sh (deps) ->
                              # install-rust.sh (niri binary) ->
                              # install-usr.sh (niri-session, session/desktop,
                              # portals, systemd user units)

      On the deck, the packaged niri from `steamos-niri.opt.pb` replaces this
      git build (see ARCH_PKGS notes in the playbook).

    # Arch package list: companions + build deps (upstream PKGBUILD
    # depends/makedepends), consumed by the archlane (gen_arch.tasks ->
    # install-arch.sh lane / render-side pacman). On the deck the packaged
    # niri from steamos-niri.opt.pb replaces this git build. cargo comes
    # from rustup, not this list.
    ARCH_PKGS:
      # companions
      - alacritty
      - fuzzel
      # resolution switching
      - kanshi
      - mako
      - swaybg
      #- swayidle
      - swaylock
      - waybar
      - xdg-desktop-portal-gtk
      - xdg-desktop-portal-gnome
      # and xwayland-satellite
      - xwayland
      - xwayland-satellite
      # build deps
      - cairo
      - clang
      - dbus
      - git
      - glib2
      - libdisplay-info
      - libinput
      - libxkbcommon
      - mesa
      - pango
      - pipewire
      - seatd
      - systemd-libs
      - wayland
      #- udiskie
    ETC_FILES:
      - name: config-overlay.kdl
        content: |
          binds {
            Mod+T hotkey-overlay-title="Open a Terminal: kitty" { spawn "kitty"; }
            Mod+D hotkey-overlay-title="Run an Application: vicinae" { spawn-sh "vicinae toggle"; }
            Alt+Grave hotkey-overlay-title="Vicinae clipboard" { spawn-sh "vicinae vicinae://extensions/vicinae/clipboard/history"; }
          }
    BINS:
      - name: install-usr.sh
        content: |
          cd "{{DIR}}/repo"
          # https://github.com/niri-wm/niri/wiki/Packaging-niri
          ln -sfv $(pwd)/resources/niri-session $GLOBAL_BINS_DIR/
          ln -sfv $(pwd)/resources/niri.desktop /usr/share/wayland-sessions/
          ln -sfv $(pwd)/resources/niri-portals.conf /usr/share/xdg-desktop-portal/
          #ln -sfv $(pwd)/resources/niri.service /usr/lib/systemd/user/
          ln -sfv $(pwd)/resources/niri.service /etc/systemd/user/
          ln -sfv $(pwd)/resources/niri-shutdown.target /etc/systemd/user/
    PKGS:
      # also: clang
      - libudev-dev
      - libgbm-dev
      - libxkbcommon-dev
      - libegl1-mesa-dev
      - libwayland-dev
      - libinput-dev
      - libdbus-1-dev
      - libsystemd-dev
      - libseat-dev
      - libpipewire-0.3-dev
      - libpango1.0-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
