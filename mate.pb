---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: mate
    APT_REPO: http://repo.mate-desktop.org/debian
    APT_DISTRIBUTION: jessie
    APT_COMPONENT: main
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks name={{NAME}}
  - include: tasks/apt.list.install.tasks name={{NAME}}-{{APT_DISTRIBUTION}}
  #- include: tasks/apt.srclist.install.tasks name={{NAME}}
  - apt: state={{APT_INSTALL}} pkg={{item}}
    with_items: WORKSTATION_MATE
