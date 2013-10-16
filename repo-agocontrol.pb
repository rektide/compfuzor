---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: agocontrol
    APT_REPO: http://mirror.at.agocontrol.com/debian
    APT_DISTRIBUTION: unstable
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  #- include: tasks/apt.key.install.tasks
  - include: tasks/apt.list.install.tasks
  #- include: tasks/apt.srclist.install.tasks
