---
- hosts: all
  vars:
    REPO: https://codeberg.org/sonusmix/sonusmix
    RUST: True
    PKGS:
      - resvg
      - libgtk-4-dev
      - libpipewire-0.3-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
