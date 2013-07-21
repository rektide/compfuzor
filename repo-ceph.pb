---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: ceph
    APT_REPO: http://eu.ceph.com/debian-cuttlefish/
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks
  - include: tasks/apt.list.install.tasks
  #- include: tasks/apt.srclist.install.tasks
