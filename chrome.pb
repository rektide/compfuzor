---
- hosts: all
  vars:
    NAME: chrome
    APT_REPO: http://dl.google.com/linux/chrome/deb
    APT_KEY: A040830F7FAC5991
    APT_DISTRIBUTION: stable
    PKGS:
    - google-chrome-unstable
  tasks:
  - action: include_defaults source=vars/common.vars
  - include: tasks/compfuzor/vars_apt.tasks
  - include: tasks/compfuzor/apt.tasks
  - include: tasks/compfuzor/pkgs.tasks
