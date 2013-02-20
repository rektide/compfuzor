---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: virtualbox
    APT_REPO: http://download.virtualbox.org/virtualbox/debian
    APT_DISTRIBUTION: wheezy
    APT_COMPONENT: contrib
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks name=$NAME
  - include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.srclist.install.tasks name=$NAME.unstable
  - apt: state=${APT_INSTALL} pkg=dkms,virtualbox-4.2
    only_if: not ${APT_BYPASS}
