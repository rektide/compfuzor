---
- hosts: all
  vars_files:
    - vars/steamos-session.yaml
  vars:
    TYPE: steamos-session
    INSTANCE: main
    # Compositor-neutral SteamOS session operators. Compositor-specific srv
    # playbooks import this one and add named convenience wrappers.
  tasks:
    - name: publish shared SteamOS session actions
      set_fact:
        BINS: "{{STEAMOS_SESSION_ACTIONS}}"
    - import_tasks: tasks/compfuzor.includes
