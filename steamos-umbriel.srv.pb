---
- hosts: all
  vars:
    TYPE: steamos-umbriel
    INSTANCE: srv
    # Durable operator tools. Switching sessions restarts SDDM and ends the
    # current graphical session; changing the default does not switch now.
    BINS:
      - name: to-umbriel.sh
        global: True
        content: |
          set -e
          steamosctl get-valid-desktop-sessions | grep -w umbriel.desktop || {
              echo "to-umbriel: umbriel.desktop is not registered; install it first" >&2
              exit 1
          }
          steamosctl switch-to-desktop-mode umbriel.desktop
      - name: to-plasma.sh
        global: True
        content: steamosctl switch-to-desktop-mode plasma.desktop
      - name: to-game.sh
        global: True
        content: |
          set -e
          steamosctl set-default-login-mode game
          steamosctl switch-to-game-mode
      - name: default-umbriel.sh
        global: True
        content: |
          set -e
          steamosctl get-valid-desktop-sessions | grep -w umbriel.desktop || {
              echo "default-umbriel: umbriel.desktop is not registered; install it first" >&2
              exit 1
          }
          steamosctl set-default-desktop-session umbriel.desktop
      - name: default-plasma.sh
        global: True
        content: steamosctl set-default-desktop-session plasma.desktop
      - name: sessions.sh
        global: True
        content: |
          printf 'login mode:      '; steamosctl get-default-login-mode
          printf 'desktop session: '; steamosctl get-default-desktop-session
          printf 'current session: '; printf '%s\n' "${XDG_CURRENT_DESKTOP:-unknown} (${XDG_SESSION_DESKTOP:-?})"
          echo
          steamosctl get-valid-desktop-sessions
          if command -v umbriel >/dev/null 2>&1; then
              umbriel --version
          else
              echo "umbriel: not installed"
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
