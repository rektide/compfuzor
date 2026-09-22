---
- hosts: all
  vars_files:
    - vars/steamos-session.yaml
  vars:
    TYPE: steamos-umbriel
    INSTANCE: srv
    # Umbriel-specific names over the shared SteamOS session operators.
    # Switching restarts SDDM and ends the current graphical session; setting
    # the default does not switch immediately.
    STEAMOS_UMBRIEL_SESSION_ACTIONS:
      - name: to-umbriel.sh
        global: True
        content: |
          exec "${DIR}/bin/to-desktop.sh" umbriel.desktop
      - name: default-umbriel.sh
        global: True
        content: |
          exec "${DIR}/bin/default-desktop.sh" umbriel.desktop
  tasks:
    - name: publish shared and Umbriel session actions
      set_fact:
        BINS: "{{ STEAMOS_SESSION_ACTIONS + STEAMOS_UMBRIEL_SESSION_ACTIONS }}"
    - import_tasks: tasks/compfuzor.includes
