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
  - include: tasks/apt.key.install.tasks name=$NAME.seed
  - include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.srclist.install.tasks name=$NAME.unstable
  - apt: state=${APT_INSTALL} pkg=x2go-keyring,x2goserver,x2godesktopsharing,x2goserver-extensions,x2go-client
