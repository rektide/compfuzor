---
- hosts: all
  vars:
    TYPE: steamos-niri
    INSTANCE: srv
    # Operator session tools for niri-on-SteamOS: live loading/unloading of
    # the desktop session plus gaming-mode return. Sits next to
    # steamos-niri.opt.pb (package convergence + install.sh re-apply after
    # steamos-update); this playbook only carries switcher commands.
    #
    # steamosctl is the whole interface (see design/niri-deck/niri-deck.glm53.md):
    #   switch-to-desktop-mode [SESSION]   live switch; restarts sddm, ends the
    #                                     current session
    #   set-default-desktop-session NAME   persistent desktop-mode choice
    #   set-default-login-mode game|desktop which mode boot/return-to lands in
    #
    # The durable copies live here in /srv (survives steamos-update). The
    # global: True links into /usr/local/bin are convenience only: that dir
    # is wiped by updates (unless steamos-offload's usr-local mount is
    # active), and re-running this playbook restores them.
    BINS:
      # load niri: switch now, without committing the default. Ends the
      # current session -- run from gamemode, plasma, or a niri you are
      # leaving for a fresh one.
      - name: to-niri.sh
        global: True
        content: |
          set -e
          steamosctl get-valid-desktop-sessions | grep -w niri.desktop || {
              echo "to-niri: niri.desktop not registered; install first:" >&2
              echo "  sudo bash /opt/steamos-niri-main/bin/install.sh" >&2
              exit 1
          }
          steamosctl switch-to-desktop-mode niri.desktop
      # unload niri: back to plasma now (plasma ships with SteamOS)
      - name: to-plasma.sh
        global: True
        content: |
          set -e
          steamosctl switch-to-desktop-mode plasma.desktop
      # "Return to Gaming Mode" from any desktop session
      - name: to-game.sh
        global: True
        content: |
          set -e
          steamosctl set-default-login-mode game
          steamosctl switch-to-game-mode
      # commit the persistent default without switching (the granular
      # counterpart of steamos-niri.opt.pb's session.sh)
      - name: default-niri.sh
        global: True
        content: |
          set -e
          steamosctl get-valid-desktop-sessions | grep -w niri.desktop || {
              echo "default-niri: niri.desktop not registered; install first:" >&2
              echo "  sudo bash /opt/steamos-niri-main/bin/install.sh" >&2
              exit 1
          }
          steamosctl set-default-desktop-session niri.desktop
      - name: default-plasma.sh
        global: True
        content: |
          set -e
          steamosctl set-default-desktop-session plasma.desktop
      # session state overview (informational, no drift semantics)
      - name: sessions.sh
        global: True
        content: |
          printf 'login mode:      '; steamosctl get-default-login-mode
          printf 'desktop session: '; steamosctl get-default-desktop-session
          printf 'current session: '; printf '%s\n' "${XDG_CURRENT_DESKTOP:-unknown} (${XDG_SESSION_DESKTOP:-?})"
          echo
          steamosctl get-valid-desktop-sessions
          if pacman -Q niri >/dev/null 2>&1; then
              pacman -Q niri
          else
              echo "niri: not installed (sudo bash /opt/steamos-niri-main/bin/install.sh)"
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
