---
- hosts: all
  #sudo: True
  tags:
  - packages
  - repo
  - root
  gather_facts: False
  vars_files:
  - vars/common.vars
  vars:
    NAME: java7
    APT_REPO: http://ppa.launchpad.net/webupd8team/java/ubuntu
    APT_KEY: EEA14886
    APT_DISTRIBUTION: raring
  tasks:
  - include: tasks/apt.key.install.tasks name="{{NAME}}.webupd8"
  - include: tasks/apt.list.install.tasks name="{{NAME}}.webupd8"
  - shell: echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  - shell: echo debconf shared/accepted-oracle-license-v1-1 seen true | /usr/bin/debconf-set-selections
  - apt: state={{APT_INSTALL}} pkg=oracle-java7-installer,oracle-java7-set-default
