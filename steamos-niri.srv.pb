---
- hosts: all
  vars_files:
    - vars/steamos-session.yaml
  vars:
    TYPE: steamos-niri
    INSTANCE: srv
    # Niri-specific convenience wrappers around steamos-session.srv.pb. Sits next to
    # steamos-niri.opt.pb (package convergence + install.sh re-apply after
    # steamos-update); this playbook only carries switcher commands.
    #
    # The durable copies live here in /srv (survives steamos-update). The
    # global: True links into /usr/local/bin are convenience only: that dir
    # is wiped by updates (unless steamos-offload's usr-local mount is
    # active), and re-running this playbook restores them.
    STEAMOS_NIRI_ACTIONS:
      # load niri: switch now, without committing the default. Ends the
      # current session -- run from gamemode, plasma, or a niri you are
      # leaving for a fresh one.
      - name: to-niri.sh
        global: True
        content: |
          exec "${DIR}/bin/to-desktop.sh" niri.desktop
      # commit the persistent default without switching (the granular
      # counterpart of steamos-niri.opt.pb's session.sh)
      - name: default-niri.sh
        global: True
        content: |
          exec "${DIR}/bin/default-desktop.sh" niri.desktop
  tasks:
    - name: publish shared and niri session actions
      set_fact:
        BINS: "{{ STEAMOS_SESSION_ACTIONS + STEAMOS_NIRI_ACTIONS }}"
    - import_tasks: tasks/compfuzor.includes
