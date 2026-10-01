---
# noctalia-greeter.src.pb -- Noctalia Greeter, a greetd login greeter with
# its own bundled wlroots compositor (greetd runs `noctalia-greeter-session`,
# which starts that compositor and shows the greeter inside it).
#
# Installs under /usr, deliberately unlike the /usr/local convention used by
# umbriel.src.pb / xdg-desktop-portal-umbriel.src.pb. The greeter's
# privileged machinery assumes a distribution prefix (upstream PACKAGING.md):
#   * polkitd only loads /usr/share/polkit-1/actions -- a policy under
#     /usr/local/share is "not normally discovered merely because the greeter
#     was built with that prefix";
#   * the installed noctalia-greeter-print-greetd-config wrapper hardcodes
#     /usr/share/noctalia-greeter/print_greetd_config.sh;
#   * tmpfiles.d and the polkit policy path are baked in relative to prefix.
# Nothing in Debian ships these paths, so there is no dpkg collision; the
# deployment state (repo, bin/, env) still lives in DIR under /usr/local/src.
#
# Scope of the install bin, by operator choice: build + meson install +
# file-mode hygiene ONLY. The system wiring is deliberately left as
# operator-invoked helpers, not playbook automation:
#   * bin/setup-greeter.sh    -- runs the upstream setup script (creates
#                                /var/lib/noctalia-greeter chowned to the
#                                greetd session user, patches greetd PAM for
#                                XDG_RUNTIME_DIR, prints a greetd block)
#   * bin/greetd-config.sh    -- prints the ready-to-paste [default_session]
#                                block for /etc/greetd/config.toml
# Switching the display manager (greetd config) stays a human decision.

- hosts: all
  vars:
    TYPE: noctalia-greeter
    INSTANCE: git
    REPO: https://github.com/noctalia-dev/noctalia-greeter
    ENV: True

    # Arch packages include their development headers. wlroots0.20 and
    # wayland-server are required (the bundled compositor is not optional);
    # libglvnd provides EGL/GLES.
    ARCH_PKGS:
      - cairo
      - dbus
      - fontconfig
      - freetype2
      - gcc
      - glib2
      - greetd
      - harfbuzz
      - libglvnd
      - libinput
      - librsvg
      - libwebp
      - libxkbcommon
      - libxml2
      - meson
      - ninja
      - nlohmann-json
      - pango
      - pkgconf
      - stb
      - tomlplusplus
      - wayland
      - wayland-protocols
      - wlroots0.20

    # Install missing source-build dependencies without turning this playbook
    # into an opportunistic workhorse graphics-stack upgrade. greetd is the
    # runtime display manager; dbus-run-session is used by the session
    # wrapper.
    APT_INSTALL: present
    PKGS:
      - build-essential
      - dbus
      - git
      - greetd
      - libcairo2-dev
      - libegl-dev
      - libfontconfig-dev
      - libfreetype-dev
      - libgles-dev
      - libglib2.0-dev
      - libharfbuzz-dev
      - libinput-dev
      - libpango1.0-dev
      - librsvg2-dev
      - libstb-dev
      - libtomlplusplus-dev
      - libwayland-dev
      - libwebp-dev
      - libwlroots-0.20-dev
      - libxkbcommon-dev
      - libxml2-dev
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
          # incremental builds (same rationale as umbriel.src.pb build.sh).
          # Note: the project's own release buildtype adds -march=native --
          # fine for this machine-local build, just not what a redistributable
          # package would use (PACKAGING.md suggests --buildtype=plain there).
          _build="${DIR}/build-release"
          git status --porcelain >/dev/null
          if [ -f "$_build/meson-private/coredata.dat" ]; then
              meson setup "$_build" --reconfigure \
                  --buildtype=release --prefix=/usr
          else
              meson setup "$_build" \
                  --buildtype=release --prefix=/usr
          fi
          meson compile -C "$_build"
      # The package lanes run first; this main-lane leaf then builds and
      # escalates only installation. System wiring (setup script, greetd
      # config) is intentionally NOT here; see the helpers below.
      - name: install-noctalia-greeter.sh
        phase: main
        basedir: repo
        content: |
          "${DIR}/bin/build.sh"
          sudo meson install -C "${DIR}/build-release"
          # Some source filesystems preserve executable data-file modes. Only
          # the assets tree is blanket-de-executable; the scripts under
          # share/noctalia-greeter (setup_greeter_system.sh and friends) must
          # KEEP their install_mode rwxr-xr-x.
          sudo find /usr/share/noctalia-greeter/assets -type f -exec chmod 0644 {} +
          sudo chmod 0644 \
              /usr/share/polkit-1/actions/org.noctalia.greeter.apply-appearance.policy \
              /usr/lib/tmpfiles.d/noctalia-greeter.conf
          # Deliberately not run here (operator choice): the upstream setup
          # script that owns /var/lib/noctalia-greeter and greetd's PAM
          # stack. Use bin/setup-greeter.sh.
      # Operator helper: one-shot system setup (state dir + PAM patch +
      # printed greetd block). Runs the upstream script as root.
      - name: setup-greeter.sh
        compose: false
        content: exec sudo /usr/share/noctalia-greeter/setup_greeter_system.sh "$@"
      # Operator helper: print the [default_session] block to merge into
      # /etc/greetd/config.toml by hand.
      - name: greetd-config.sh
        compose: false
        content: exec /usr/bin/noctalia-greeter-print-greetd-config "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
