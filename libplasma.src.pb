---
- hosts: all
  vars:
    REPO: https://invent.kde.org/plasma/libplasma
    CMAKE: True
    PKGS:
      - libkirigami-dev
      - libkf6iconthemes-dev
      - libkf6svg-dev
      - libplasmaactivities-dev
      - libkf6svg-dev
      - libkf6svg-dev
      - qt6-base-dev
      - qt6-declarative-dev
      - qt6-wayland-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
