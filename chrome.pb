---
- hosts: all
  sudo: True
  gather_facts: False
  vars:
    NAME: chrome
    APT_REPO: http://dl.google.com/linux/chrome/deb
    APT_KEY: A040830F7FAC5991
    APT_DISTRIBUTION: stable
  vars_files: 
    - vars/common.vars
  tasks:
  - include: tasks/apt.key.install.tasks
  - include: tasks/apt.list.install.tasks
  - apt: pkg=google-chrome-unstable state={{APT_INSTALL}}
