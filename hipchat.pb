---
- hosts: all
  vars:
    NAME: hipchat
    APT_REPO: "http://downloads.hipchat.com/linux/apt"
    APT_DISTRIBUTION: stable
    #APT_TRUST: false
    PKGS:
    - hipchat
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/compfuzor.includes type=opt
  #- include: tasks/apt.list.install.tasks
