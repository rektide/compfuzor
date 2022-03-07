---
- hosts: all
  vars:
    TYPE: chrome
    INSTANCE: apt
    APT_REPO: http://dl.google.com/linux/chrome/deb
    APT_KEY: 78BD65473CB3BD13
    APT_DISTRIBUTION: stable
    PKGS:
    - google-chrome-unstable
  tasks:
  - action: include_defaults file=common.yaml
  - include: tasks/compfuzor/vars_apt.tasks
  - include: tasks/compfuzor/apt.tasks
  - include: tasks/compfuzor/pkgs.tasks
