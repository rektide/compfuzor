---
- hosts: all
  gather_facts: False
  vars:
    NAME: chrome
    APT_REPO: http://dl.google.com/linux/chrome/deb
    APT_KEY: A040830F7FAC5991
    APT_DISTRIBUTION: stable
    PKGS:
    - google-chrome-unstable
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/compfuzor/vars_apt.tasks
  - include: tasks/compfuzor/apt.tasks
  - include: tasks/compfuzor/pkgs.tasks
