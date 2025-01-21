---
- hosts: all
  vars:
    TYPE: chrome
    INSTANCE: stable
    APT_REPO: http://dl.google.com/linux/chrome/deb
    APT_KEY: E88979FB9B30ACF2
    APT_DISTRIBUTION: stable
    APT_TRUSTED: chrome-apt
    APT_SOURCELIST: chrome-apt
    PKGS:
    - google-chrome-unstable
  tasks:
    - import_tasks: tasks/compfuzor.includes
