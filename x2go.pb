---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: x2go
    APT_REPO: http://packages.x2go.org/debian
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks name=$NAME
  - include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.list.install.tasks name=$NAME.unstable.src 
  #- apt: state=${APT_INSTALL} pkg=
