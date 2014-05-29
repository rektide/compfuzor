---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: pali
    APT_REPO: http://ppa.launchpad.net/pali/pali/ubuntu
    APT_DISTRIBUTION: oneiric
  vars_files:
  - vars/common.vars
  tasks:
  #- include: tasks/compfuzor.includes
  #- include: tasks/apt.key.install.tasks
  - include: tasks/apt.list.install.tasks
  #- include: tasks/apt.srclist.install.tasks
