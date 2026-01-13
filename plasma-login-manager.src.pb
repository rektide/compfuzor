---
- hosts: all
  vars:
    REPO: https://github.com/KDE/plasma-login-manager
    CMAKE: True
    PKGS:
      - libkf6package-dev
      - libkf6windowsystem-dev
      - libkf6auth-dev
      - libkf6auth-dev-bin
      - libkf6kio-devs
      - libkf6auth-dev
      - libkf6auth-dev-bin
      - libkf6package-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
