---
- hosts: all
  vars:
    TYPE: steamos-niri
    INSTANCE: main
    # niri as the SteamOS desktop-mode session on deck, replacing plasma.
    # Gamemode/gamescope is untouched: steamosctl owns the session switch.
    # Assessment: design/niri-deck/niri-deck.glm53.md
    #
    # SteamOS updates wipe /usr (and re-enable steamos-readonly), so after
    # any steamos-update re-apply from this DIR:
    #   sudo bash bin/install.sh   # readonly disable + archlane pacman --needed
    #   bin/install-user.sh        # adopt root + assemble keybindings
    #   bin/session.sh             # steamosctl set-default-desktop-session
    #
    # Deck binds are declared through the keybindings producer system
    # (doc/config/keybinding-producers.md): this deployment is BOTH the
    # Niri consumer host (KEYBINDING_CONSUMERS) and the owner of its own
    # late user layer (KEYBINDING_ACTIONS/KEYBINDINGS with no producer
    # targets -- the declarations package into the generated profile, no
    # membership groups, no separate producer deployment to survive wipes).
    # The old hand-written etc/config-overlay.kdl include is retired by
    # install-user.sh as a one-time migration; the file itself stays on
    # disk unreferenced. Runtime prerequisites (node, jq) ride ARCH_PKGS;
    # the apt lane the generator contributes self-gates off (no apt on
    # SteamOS).
    ARCH_PKGS:
      # the switch itself (all in the deck's extra-3.9 snapshot)
      - niri
      - xwayland-satellite
      # portal screencast/screenshot; pulls ~35 gnome-ish packages, comment
      # out if the 5G root is tight (builtin niri screenshots still work)
      - xdg-desktop-portal-gnome
      # shell
      - alacritty
      - fuzzel
      - kanshi
      - mako
      - swaybg
      - swaylock
      - waybar
      # deck desktop-mode niceties: brightness keys, touchscreen OSK
      - brightnessctl
      - squeekboard
      # keybindings host assembly runtime (bundled .mjs through node; jq
      # for the CONFIG workers) -- the deck renders this playbook locally
      - nodejs
      - jq
    KEYBINDING_CONSUMERS:
      niri:
        contexts:
          user: {scope: user, root: config, subpath: niri}
    KEYBINDING_ACTIONS:
      deck-terminal:
        exec: [ghostty]
      deck-steam-couch:
        # couch mode: full Steam Deck UI nested in gamescope
        script: {shell: sh, body: "gamescope -W 1280 -H 800 -f -e -- steam -gamepadui -steamdeck"}
      deck-brightness-down:
        exec: [brightnessctl, set, 5%-]
      deck-brightness-up:
        exec: [brightnessctl, set, +5%]
      deck-volume-up:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", 5%+]
      deck-volume-down:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", 5%-]
      deck-volume-mute:
        exec: [wpctl, set-mute, "@DEFAULT_AUDIO_SINK@", toggle]
    KEYBINDINGS:
      deck-terminal:
        action: deck-terminal
        keys: [Mod+T]
        title: "Open a Terminal: ghostty"
      deck-steam-couch:
        action: deck-steam-couch
        keys: [Mod+G]
        title: "Steam Deck UI (gamescope)"
      deck-brightness-down:
        action: deck-brightness-down
        keys: [XF86MonBrightnessDown]
      deck-brightness-up:
        action: deck-brightness-up
        keys: [XF86MonBrightnessUp]
      deck-volume-up:
        action: deck-volume-up
        keys: [XF86AudioRaiseVolume]
      deck-volume-down:
        action: deck-volume-down
        keys: [XF86AudioLowerVolume]
      deck-volume-mute:
        action: deck-volume-mute
        keys: [XF86AudioMute]
    BINS:
      # body runs first, then composed run_all lanes: install-arch.sh
      # (archlane) converges ARCH_PKGS with pacman --needed after it.
      - name: install.sh
        content: |
          sudo steamos-readonly disable
      # make niri the SteamOS desktop-mode session; fails loudly if
      # niri.desktop is not yet registered (run install.sh first)
      - name: session.sh
        content: |
          set -e
          steamosctl get-valid-desktop-sessions
          steamosctl get-valid-desktop-sessions | grep -w niri.desktop
          steamosctl set-default-desktop-session niri.desktop
          steamosctl get-default-desktop-session
      - name: session-plasma.sh
        content: |
          # rollback: desktop mode back to plasma (plasma stays installed)
          steamosctl set-default-desktop-session plasma.desktop
      # Adopt the deck's live niri root (managed insertion-area markers;
      # retire the superseded config-overlay.kdl include line once), keep
      # the mako companion. gen_bins then appends the generated
      # install-keybindings-niri.sh child: host assembly rebuilds the
      # managed area from this deployment's packaged declarations and
      # validates the full closure with the installed niri binary.
      - name: install-user.sh
        deployment_rooted: True
        content: |
          NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
          NIRI_CONFIG="$NIRI_DIR/config.kdl"
          mkdir -p "$NIRI_DIR"
          if [ ! -e "$NIRI_CONFIG" ]; then
            # missing root: minimal managed-area skeleton
            printf '// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n' > "$NIRI_CONFIG"
          elif ! grep -qx '// compfuzor-keybindings-begin' "$NIRI_CONFIG"; then
            # existing root without the adopted area: append the marker pair
            # at EOF (trailing top-level comments are valid KDL); existing
            # text -- output blocks, steamos session config, personal binds --
            # is never rewritten.
            printf '\n// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n' >> "$NIRI_CONFIG"
          fi
          # One-time migration: the deck binds now live in the managed area
          # as this deployment's packaged declarations; retire the old
          # config-overlay.kdl include line (idempotent).
          if grep -qF 'config-overlay.kdl' "$NIRI_CONFIG"; then
            sed -i '\#config-overlay\.kdl#d' "$NIRI_CONFIG"
          fi
          # mako as a supervised session companion; niri's default config
          # already spawn-at-startup's waybar
          systemctl --user add-wants niri.service mako.service || true
    README: |
      # steamos-niri.opt.pb

      Opt-typed deck deployment (persistent `/opt/steamos-niri-main`) making
      niri the SteamOS desktop-mode session. Binds are declared through the
      keybindings system: this deployment hosts the Niri consumer profile and
      owns its own late user layer; `install-user.sh` adopts
      `~/.config/niri/config.kdl` (marker pair at EOF, old overlay include
      retired once) and rebuilds the managed insertion area with native
      validation.

      ## Re-apply after any steamos-update (SteamOS wipes /usr)

      ```sh
      sudo bash bin/install.sh
      bin/install-user.sh
      bin/session.sh
      ```

      Requires node, jq and niri (all in ARCH_PKGS) on PATH at invocation
      time; the apt lane self-gates off on Arch-family hosts.
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        # write into persistent ext4 /opt
        type: opt
