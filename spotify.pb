---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: spotify
    APT_REPO: http://repository.spotify.com
    APT_DISTRIBUTION: stable
    APT_COMPONENT: non-free
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks name=$NAME
  - include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.srclist.install.tasks name=$NAME.unstable
  - apt: state=${APT_INSTALL} pkg=spotify-client
