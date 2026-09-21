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
    #   bin/session.sh             # steamosctl set-default-desktop-session
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
    ETC_FILES:
      - name: config-overlay.kdl
        content: |
          // deck niri binds; wired into ~/.config/niri/config.kdl by
          // bin/user-config.sh (niri include). niri live-reloads on save.
          binds {
              Mod+T hotkey-overlay-title="Open a Terminal: ghostty" { spawn "ghostty"; }
              // couch mode: full Steam Deck UI nested in gamescope
              Mod+G hotkey-overlay-title="Steam Deck UI (gamescope)" { spawn-sh "gamescope -W 1280 -H 800 -f -e -- steam -gamepadui -steamdeck"; }
              XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
              XF86MonBrightnessUp { spawn "brightnessctl" "set" "+5%"; }
              XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
              XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
              XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
          }
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
      - name: user-config.sh
        content: |
          set -e
          mkdir -p "$HOME/.config/niri"
          _cfg="$HOME/.config/niri/config.kdl"
          _inc="include \"${DIR}/etc/config-overlay.kdl\""
          if [ ! -e "$_cfg" ]; then
              printf '%s\n' "$_inc" > "$_cfg"
          elif ! grep -Fq config-overlay.kdl "$_cfg"; then
              printf '\n%s\n' "$_inc" >> "$_cfg"
          fi
          # mako as a supervised session companion; niri's default config
          # already spawn-at-startup's waybar
          systemctl --user add-wants niri.service mako.service || true
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        # write into persistent ext4 /opt
        type: opt
