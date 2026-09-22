---
- hosts: all
  vars_files:
    - vars/umbriel.yaml
  vars:
    TYPE: steamos-umbriel
    INSTANCE: main
    REPO: https://github.com/noctalia-dev/umbriel
    ENV: True

    # /opt and the archive checkout persist across SteamOS image swaps. /usr
    # does not, so one unprivileged `bash bin/install.sh` after an update
    # disables readonly mode, converges packages, clean-builds Umbriel, and
    # installs its binary/session/user units back into the active image.
    UMBRIEL_PREFIX: /usr
    UMBRIEL_CLEAN_BUILD: true

    PKGS: "{{UMBRIEL_PKGS}}"
    ARCH_PKGS: "{{UMBRIEL_ARCH_PKGS}}"
    STEAMOS_UMBRIEL_ACTIONS:
      # Authored compositor body runs before the packages/main children.
      - name: install.sh
        content: |
          sudo steamos-readonly disable
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
        content: |
          steamosctl set-default-desktop-session plasma.desktop
  tasks:
    - name: publish Umbriel and SteamOS actions
      set_fact:
        BINS: "{{ UMBRIEL_ACTIONS + STEAMOS_UMBRIEL_ACTIONS }}"
    - import_tasks: tasks/compfuzor.includes
      vars:
        # Persistent SteamOS home-partition offload.
        type: opt
